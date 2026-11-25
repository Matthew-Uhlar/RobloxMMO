// Organic world shapes (docs/DEPTH-CONTRACT.md §55): the gather-node and decor
// trees, rocks, ore veins, crops, plants and depleted nodes, re-authored to the
// §54 organic bar (98 % of shading normals by area within 15 degrees of their
// face, <= 2 % of edges sharper than 35 degrees, rings and blobs subdivided for
// their placed size, meta.maxScale). Loaded by art/generate-props.cjs after
// art/world-shapes.cjs (same frames, fits and silhouettes as before: units are
// studs at scale 1, +Y up, the base on y = 0, fronts face -Z).
//
// §55 QC H2 (phones): every near shape stays within 4k triangles (CliffPiece
// 2.5k, TilledSoil 1k, FlowerPatch / CropBloom / CropGlowcap 3k) and each one
// has a far LOD `<Name>Far` (<= 1.2k triangles, SEG_FAR subdivision, the same
// fit box) that forge.client.lua places beyond ~40 studs on phones / ~150 on
// desktop (and always on phones for a near shape over 3k).
//
// Construction rules:
//   * trunks are flared lathes (buttress lobes from a smooth cosine of the
//     angle, bark streaks from fbm), bent by a smooth wobble, never stacked tubes;
//   * branches and roots are faired tubes (rounded, graded radii);
//   * canopies, needle tiers, mushroom caps and stones are lathed ellipsoids or
//     filleted profiles whose radius is displaced by multi-octave fbm of the
//     surface direction (lumps, scallops, strata), with `sphere` entries so the
//     forge bends the foliage normals toward the crown centre;
//   * crystals are soft hexagonal spindles (a cos(6 theta) section, rounded
//     tips) - they read as cut gems while every edge stays under 35 degrees;
//   * blossoms, berries, moss and ore glints are colour fields painted on the
//     surface (per-vertex colour keeps their family seam crisp), not jewels.
'use strict';
const OK = require('./organic-kit.cjs');
module.exports = ({ world, C, PI, hash }) => {
  const { TINT, TINT_DARK, TINT_LIGHT } = C;
  const P = (pts, rc, stepDeg = 20, maxLen = Infinity) => OK.rounded(pts, rc, { stepDeg, maxLen });
  const lat = (kit, profile, opts = {}) => kit.lathe(profile, { turn: 1, ...opts });
  // Segments for a ring of radius r at placed scale s (<= 2 studs a piece, even, >= min).
  const segs = (r, s, min = 16) => { const n = Math.max(min, Math.ceil(2 * PI * r * s / 1.9)); return n + (n % 2); };
  // Far LOD segments (SEG_FAR 3.5 studs; the logged radius of a jittered lathe is 1.2 r).
  const fsegs = (r, s) => { const n = Math.max(16, Math.ceil(2 * PI * r * 1.2 * s / 3.4)); return n + (n % 2); };
  const fbm = OK.fbm, sstep = OK.sstep;
  // A near shape and its far LOD (same meta and fit box; lod / far link them).
  const organic = (name, meta, near, far) => {
    world(name, { ...meta, far: name + 'Far' }, near);
    world(name + 'Far', { ...meta, lod: 'far' }, far);
  };

  // A lumpy crown / stone: a lathed ellipsoid (radius r, half-heights hb below
  // and ht above) whose surface is pushed out by fbm of its direction.
  // color(c, up) gets the face centre (crown-local) and its height fraction.
  const lump = (kit, { pos = [0, 0, 0], rot = [0, 0, 0], r = 1, hb = r, ht = r, sx = 1, sz = 1, seed = 1, amp = .07, freq = 1.3, steps = 6, minSteps = 6, s = 1, n, color }) => {
    const prof = OK.ellipsoid(r, 0, hb, ht, Math.max(steps, minSteps)), N = n || segs(r * Math.max(sx, sz), s, 24);
    const dir = (l, i) => { const [pr, py] = prof[l], a = i * 2 * PI / N; return [pr / r * Math.cos(a) * sx, py / Math.max(hb, ht), pr / r * Math.sin(a) * sz]; };
    kit.group({ pos, rot }, () => lat(kit, prof, {
      n: N, sx, sz,
      jitter: (l, i) => 1 + amp * Math.min(1, 1.6 * Math.min(hb, ht) / r) * fbm(dir(l, i), freq, seed, 2),
      lift: (l, i) => prof[l][1] * amp * .8 * fbm(dir(l, i), freq, seed + 7, 2),
      color: (l, i, c) => color(c, c[1] >= 0 ? c[1] / ht : c[1] / hb),
    }));
  };
  // Far LOD lump: 4 steps a half, SEG_FAR ring.
  const flump = (kit, o) => lump(kit, { amp: .05, ...o, steps: o.steps || 4, minSteps: o.steps || 4, n: o.n || fsegs(o.r * Math.max(o.sx || 1, o.sz || 1), o.s || 1) });
  // Foliage field: lit crown, darker underside, painted patches and optional
  // accent spots (blossoms, berries, fruit) where fbm peaks.
  const leaves = (seed, accent, accentAt = .5) => (c, up) => {
    const f = fbm([c[0] * .9, c[1] * .9, c[2] * .9], 1, seed, 2);
    if (accent && up > -.2 && fbm([c[0] * 2.2, c[1] * 2.2, c[2] * 2.2], 1, seed + 3, 2) > accentAt) return accent;
    if (up > .45 + .2 * f) return TINT_LIGHT;
    if (up < -.25 + .15 * f) return TINT_DARK;
    return f > .3 ? TINT_LIGHT : f < -.35 ? TINT_DARK : TINT;
  };
  // Stone field: moss on the top, lighter upper faces, dark foot, fbm mottling.
  const stoneField = (seed, moss = true, tint = false) => (c, up) => {
    const f = fbm([c[0] * .8, c[1] * .8, c[2] * .8], 1, seed, 2);
    if (moss && up > .5 + .25 * f) return C.MOSS;
    if (tint) return up > .35 + .2 * f ? TINT_LIGHT : up < -.2 ? TINT_DARK : TINT;
    return up > .4 + .2 * f ? C.STONE_LIGHT : up < -.2 + .1 * f ? C.STONE_DARK : f > .35 ? C.STONE_LIGHT : C.STONE;
  };
  // A flared, bent trunk: profile up the Y axis (rounded foot below ground,
  // rounded top inside the crown), buttress lobes at the foot, a smooth bend
  // `bend(t)` -> [dx, dz], bark streaks.
  const trunk = (kit, { h, r0, r1, flare = .35, lobes = 5, seed = 1, bend = () => [0, 0], s = 1, n, bark = C.BARK, dark = C.BARK_DARK, top = true, base = 0, stepDeg = 18 }) => {
    // The foot opens 0.4 below the ground (buried, never seen).
    const rb = r0 * (1 + flare), pts = [[rb, base - .4], [rb, base + .05], [r0 * (1 + flare * .35), base + h * .1], [r0, base + h * .22], [(r0 + r1) / 2, base + h * .6], [r1, base + h]];
    if (top) pts.push([0, base + h + r1 * .4]);
    const prof = P(pts, [0, rb * .9, r0 * .8, h * .3, h * .3, r1 * .6], stepDeg, h / 7);
    const N = n || segs(r0 * (1 + flare), s, 24);
    lat(kit, prof, {
      n: N,
      jitter: (l, i) => { const y = prof[l][1], a = i * 2 * PI / N; return 1 + flare * .28 * sstep(h * .3, base, y) * (1 + Math.cos(lobes * a + seed)) / 2 + .02 * fbm([Math.cos(a), y * .4, Math.sin(a)], 1.2, seed, 2); },
      wobble: (l) => bend((prof[l][1] - base) / h),
      color: (l, i, c) => { const a = Math.atan2(c[2], c[0]), f = fbm([Math.cos(a) * 1.5, c[1] * .35, Math.sin(a) * 1.5], 1.2, seed + 5, 2); return f > .25 || c[1] < base + h * .05 ? dark : bark; },
    });
  };
  // Far LOD trunk: a plain flared taper closed at the top, SEG_FAR ring.
  const ftrunk = (kit, { h, r0, r1, s = 1, bark = C.BARK, dark = C.BARK_DARK, bend = () => [0, 0], base = 0 }) => {
    const prof = P([[r0 * 1.3, base - .4], [r0 * 1.25, base + .05], [r0, base + h * .25], [r1, base + h], [0, base + h + r1 * .5]], [0, r0 * .5, h * .25, r1 * .6], 26, h / 3);
    lat(kit, prof, { n: fsegs(r0 * 1.3, s) - 4 > 16 ? fsegs(r0 * 1.3, s) : 16, wobble: (l) => bend((prof[l][1] - base) / h),
      color: (l, i, c) => c[1] < base + h * .08 ? dark : bark });
  };
  // A branch / root: a faired tapering tube, open where it enters a trunk or crown.
  const limb = (kit, pts, r0, r1, color = C.BARK, opts = {}) => kit.tube(pts, i => r0 + (r1 - r0) * i / (pts.length - 1), { n: 16, color, capStart: false, capEnd: false, ...opts });
  // A soft hexagonal crystal: spindle profile (base buried, rounded tip),
  // section r * (1 + .07 cos 6 theta) (six soft facets), lit facets alternate.
  const crystal = (kit, { pos, rot = [0, 0, 0], len, r, seed = 1, s = 1, base = C.STONE_DARK, stepDeg = 20, n, tipSteps = 3 }) => kit.group({ pos, rot }, () => {
    const tip = [r * .42, len * .86], prof = [...P([[r * .8, -.3 * len], [r, len * .05], [r * 1.04, len * .6], tip], [0, r * .4, r * 1.2], stepDeg), ...OK.dome(tip[0], tip[1], len * .14, tipSteps)];
    const N = n || segs(r, s, 24);
    lat(kit, prof, { n: N, phase: hash(seed, 2, 1),
      jitter: (l, i) => 1 + .025 * Math.cos(6 * i * 2 * PI / N),
      color: (l, i, c) => { if (c[1] < len * .02) return base; const face = Math.floor(((Math.atan2(c[2], c[0]) / (2 * PI) + 1) * 6 + .5)) % 6; return c[1] > len * .8 ? TINT_LIGHT : face % 2 ? TINT : face === 0 ? TINT_LIGHT : TINT_DARK; } });
  });
  const fcrystal = (kit, o) => crystal(kit, { ...o, stepDeg: 30, n: 16, tipSteps: 2 });

  // =========================================================================
  // Trees (gather nodes and decor). Foliage uses the tint slots.
  // =========================================================================
  // Windpine: a straight tapering trunk and five drooping, scalloped needle
  // tiers (rounded rims, darker undersides, lit tips).
  const pineTier = (kit, r, y, t, S, stepDeg, N) => {
    const sc = 7 - t, ph = t * .9;
    const prof = P([[0, y + .25], [r * .55, y - .02], [r, y - .3], [r * .9, y - .05], [r * .55, y + .7], [r * .22, y + 1.5], [0, y + 2.1]], [0, r * .2, r * .12, r * .15, r * .3, r * .2], stepDeg);
    lat(kit, prof, { n: N, phase: ph,
      // Scalloped, drooping rim: the outer levels dip between needle tufts.
      jitter: (l, i) => 1 + .035 * Math.cos(sc * i * 2 * PI / N) * sstep(r * .5, r, prof[l][0]),
      lift: (l, i) => -.12 * ((1 + Math.cos(sc * i * 2 * PI / N)) / 2) * sstep(r * .55, r, prof[l][0]),
      color: (l, i, c) => c[1] < y - .12 ? TINT_DARK : c[1] > y + .9 + .3 * fbm([c[0], c[1], c[2]], .8, 40 + t, 2) ? TINT_LIGHT : TINT });
  };
  organic('WindpineTree', { smooth: 50, tint: '4F8A57', kind: 'tree', maxScale: 2.8 }, kit => {
    const S = 2.8;
    trunk(kit, { h: 13.2, r0: .62, r1: .1, flare: .4, lobes: 5, seed: 3, s: S, n: 24 });
    [[3.0, 3.0], [2.4, 5.6], [1.7, 8.2], [1.0, 10.8]].forEach(([r, y], t) => pineTier(kit, r, y, t, S, 20, segs(r, S, 20)));
  }, kit => {
    ftrunk(kit, { h: 12.6, r0: .62, r1: .1, s: 2.8 });
    // Two broad needle cones.
    [[3.0, 3.0, 4.6], [2.0, 7.2, 5.4]].forEach(([r, y, h], t) => lat(kit, P([[0, y + .2], [r, y - .3], [r * .2, y + h - .2], [0, y + h]], [0, r * .15, r * .1], 30), { n: fsegs(r, 2.8),
      color: (l, i, c) => c[1] < y - .12 ? TINT_DARK : c[1] > y + .4 * h ? TINT_LIGHT : TINT }));
  });
  // Emberoak: a massive flared trunk forking into four limbs under a broad,
  // lumpy crown of six blended lobes (ember leaves, lit tops).
  organic('EmberoakTree', { smooth: 55, tint: 'C9572F', kind: 'tree', maxScale: 2, sphere: [[0, 7.9, 0, 4.4, .55]] }, kit => {
    trunk(kit, { h: 4.8, r0: 1.0, r1: .62, flare: .45, lobes: 6, seed: 7, s: 2, bend: t => [.15 * Math.sin(t * PI), .1 * t], top: false });
    const limbs = [[[0, 4.0, 0], [1.6, 5.4, .3], [2.8, 6.6, .5]], [[0, 4.1, 0], [-1.5, 5.6, -.4], [-2.7, 6.4, -.8]], [[0, 4.2, 0], [-.3, 6.0, 1.4], [-.4, 7.1, 2.3]], [[0, 4.3, 0], [.4, 6.4, -1.2], [.8, 7.6, -1.6]]];
    for (const l of limbs) limb(kit, l, .5, .2);
    const crowns = [[0, 8.6, .1, 2.8], [2.8, 7.2, .5, 2.2], [-2.7, 7.0, -.8, 2.3], [-.4, 7.9, 2.2, 2.1], [.8, 8.4, -1.6, 2.2]];
    crowns.forEach(([x, y, z, r], i) => lump(kit, { pos: [x, y, z], r: r * 1.05, hb: r * .62, ht: r * .85, sz: .96, seed: 30 + i, amp: .07, s: 2, steps: 4, color: leaves(30 + i) }));
  }, kit => {
    ftrunk(kit, { h: 6.2, r0: 1.0, r1: .62, s: 2, bend: t => [.15 * Math.sin(t * PI), .1 * t] });
    flump(kit, { pos: [0, 8.0, .1], r: 4.4, hb: 1.9, ht: 2.6, sz: .96, seed: 30, s: 2, color: leaves(30) });
  });
  // Starwood: an ink-dark leaning trunk carrying four star-lit platters
  // (scalloped rims, bright flame motes painted on top) and a flame finial.
  const platter = (kit, r, y, dx, t, N, stepDeg) => {
    const prof = P([[0, y - .3], [r * .7, y - .42], [r, y - .1], [r * .8, y + .3], [r * .3, y + .5], [0, y + .56]], [0, r * .25, r * .14, r * .3, r * .2], stepDeg);
    lat(kit, prof, { n: N, phase: t * .5, wobble: () => [dx, 0],
      color: (l, i, c) => c[1] < y - .15 ? TINT_DARK : c[1] > y + .32 && fbm([c[0] * 2, c[1], c[2] * 2], 1, 66 + t, 2) > .42 ? C.FLAME : c[1] > y + .2 ? TINT_LIGHT : TINT });
  };
  organic('StarwoodTree', { smooth: 50, tint: '46599A', kind: 'tree', maxScale: 2 }, kit => {
    trunk(kit, { h: 10.6, r0: .7, r1: .18, flare: .35, lobes: 5, seed: 61, s: 2, bark: C.NAVY, dark: C.INK, bend: t => [.35 * Math.sin(t * PI * 1.5), .1 * Math.sin(t * PI)] });
    for (const [r, y, dx, t] of [[3.4, 4.6, .3, 0], [2.9, 6.8, -.25, 1], [2.2, 8.9, .2, 2], [1.4, 10.7, 0, 3]]) platter(kit, r, y, dx, t, segs(r, 2, 24), 20);
    lat(kit, OK.ellipsoid(.36, 11.3, .3, 1.1, 4), { n: 16, color: (l, i, c) => c[1] > 11.6 ? C.FLAME : C.AMBER, wobble: () => [.02, 0] });
  }, kit => {
    ftrunk(kit, { h: 10.4, r0: .7, r1: .18, s: 2, bark: C.NAVY, dark: C.INK, bend: t => [.35 * Math.sin(t * PI * 1.5), .1 * Math.sin(t * PI)] });
    for (const [r, y, dx, t] of [[3.4, 4.6, .3, 0], [2.5, 7.8, 0, 2]]) platter(kit, r, y, dx, t, fsegs(r, 2), 36);
  });
  // Aetherheart: a colossal buttressed trunk lifted on arching roots, a glowing
  // heart crystal set in a bark hollow, four limbs and a vast lumpy crown hung
  // with flame-coloured blossoms.
  organic('AetherheartTree', { smooth: 50, tint: 'E8D98E', kind: 'tree', maxScale: 2, sphere: [[0, 11.4, 0, 5.4, .55]] }, kit => {
    trunk(kit, { h: 8.6, r0: 1.4, r1: .95, flare: .5, lobes: 6, seed: 71, s: 2, base: 1.6, top: false, bend: t => [.1 * Math.sin(t * PI), 0] });
    for (let i = 0; i < 3; i++) {
      const a = i * 2 * PI / 3 + .3, r = 3.4 + hash(i, 73, 1);
      limb(kit, [[Math.cos(a) * .9, 2.6, Math.sin(a) * .9], [Math.cos(a) * 2.2, 2.3, Math.sin(a) * 2.2], [Math.cos(a) * r, .9, Math.sin(a) * r], [Math.cos(a) * (r + .5), -.1, Math.sin(a) * (r + .5)]], .55, .25, C.BARK, { capEnd: true, turn: .45, capSteps: 3 });
    }
    // The heart: a glowing soft-cut crystal set in the bark.
    kit.group({ pos: [0, 4.6, -1.36], rot: [-PI / 2, 0, 0] }, () => {
      lat(kit, OK.ellipsoid(.42, .18, .28, .44, 5), { n: 16, sz: .7, color: (l, i, c) => c[1] > .4 ? C.GLINT : TINT_LIGHT });
    });
    const limbs = [[3.2, 9.6, 0], [-3.0, 9.8, .8], [.6, 10.3, 3.0], [-.4, 10.2, -3.0]];
    for (const [x, y, z] of limbs) limb(kit, [[0, 8.6, 0], [x * .5, y - .6, z * .5], [x, y, z]], .55, .24);
    lump(kit, { pos: [0, 11.6, 0], r: 4.4, hb: 1.6, ht: 2.5, seed: 74, amp: .08, s: 2, color: leaves(74, C.FLAME, .62) });
    limbs.slice(0, 2).forEach(([x, y, z], i) => lump(kit, { pos: [x * 1.05, y + .4, z * 1.05], r: 2.3, hb: .95, ht: 1.3, seed: 80 + i, amp: .07, s: 2, steps: 4, color: leaves(80 + i, C.FLAME, .62) }));
  }, kit => {
    ftrunk(kit, { h: 9.4, r0: 1.5, r1: .95, s: 2, bend: t => [.1 * Math.sin(t * PI), 0] });
    flump(kit, { pos: [0, 11.4, 0], r: 5.6, hb: 2.0, ht: 2.8, seed: 74, s: 2, color: leaves(74, C.FLAME, .62) });
  });
  // Meadow tree: a short bent trunk, two boughs and a three-lobed round crown
  // dotted with rose blossoms.
  organic('MeadowTree', { smooth: 55, tint: '6BAF5A', kind: 'tree', maxScale: 2, sphere: [[0, 6.2, 0, 3.4, .55]] }, kit => {
    trunk(kit, { h: 3.8, r0: .55, r1: .36, flare: .4, lobes: 4, seed: 91, s: 2, top: false, bend: t => [.1 * Math.sin(t * PI), .05 * t] });
    limb(kit, [[0, 3.2, 0], [1.1, 4.4, .2], [1.7, 5.4, .3]], .26, .12);
    limb(kit, [[0, 3.4, 0], [-1, 4.6, -.3], [-1.5, 5.6, -.4]], .26, .12);
    lump(kit, { pos: [0, 6.3, 0], r: 2.6, hb: 1.5, ht: 2.0, sz: .96, seed: 93, amp: .07, s: 2, color: leaves(93, C.ROSE, .58) });
    lump(kit, { pos: [1.8, 5.6, .4], r: 1.6, hb: .95, ht: 1.25, seed: 94, amp: .07, s: 2, steps: 4, color: leaves(94, C.ROSE, .58) });
    lump(kit, { pos: [-1.7, 5.7, -.4], r: 1.65, hb: .98, ht: 1.3, seed: 95, amp: .07, s: 2, steps: 4, color: leaves(95, C.ROSE, .58) });
  }, kit => {
    ftrunk(kit, { h: 4.8, r0: .55, r1: .36, s: 2, bend: t => [.1 * Math.sin(t * PI), .05 * t] });
    flump(kit, { pos: [0, 6.1, 0], r: 3.2, hb: 1.7, ht: 2.1, sx: 1.08, seed: 93, s: 2, color: leaves(93, C.ROSE, .58) });
  });
  // Canopy tree (Windpine grove decor): a tall trunk on four arching roots
  // under four stacked, flattened leaf tiers.
  organic('CanopyTree', { smooth: 50, tint: '5E9C4E', kind: 'tree', maxScale: 2 }, kit => {
    trunk(kit, { h: 8.4, r0: .7, r1: .22, flare: .3, lobes: 4, seed: 51, s: 2, bend: t => [.2 * Math.sin(t * PI * 1.3), .08 * Math.sin(t * PI)] });
    for (let k = 0; k < 4; k++) { const a = k * PI / 2 + .4; limb(kit, [[0, .9, 0], [Math.cos(a) * 1.1, .3, Math.sin(a) * 1.1], [Math.cos(a) * 1.7, -.05, Math.sin(a) * 1.7]], .3, .1, C.BARK, { capEnd: true }); }
    const tiers = [[3.8, 3.6, .9], [3.1, 5.4, .8], [2.3, 7.1, .7], [1.4, 8.6, .6]];
    tiers.forEach(([r, y, h], t) => lump(kit, { pos: [(t % 2 ? .3 : -.2), y, (t % 2 ? -.2 : .25)], r, hb: h * .7, ht: h * 1.1, seed: 520 + t, amp: .08, s: 2, steps: 4, color: leaves(520 + t) }));
  }, kit => {
    ftrunk(kit, { h: 8.2, r0: .7, r1: .22, s: 2, bend: t => [.2 * Math.sin(t * PI * 1.3), .08 * Math.sin(t * PI)] });
    [[3.8, 3.8, 1.0], [2.5, 6.9, .9]].forEach(([r, y, h], t) => flump(kit, { pos: [(t % 2 ? .3 : -.2), y, (t % 2 ? -.2 : .25)], r, hb: h * .7, ht: h * 1.1, seed: 520 + t, s: 2, color: leaves(520 + t) }));
  });
  // Palm: a ringed trunk curving out, seven drooping fronds (lofted blades with
  // a midrib), three coconuts.
  const palmTrunk = (kit, k9) => {
    const trunkPts = [];
    for (let k = 0; k <= k9; k++) { const t = k / k9; trunkPts.push([1.3 * t * t, t * 6.4, .1 * Math.sin(t * PI)]); }
    kit.tube(trunkPts, i => .44 - i * .026 * 9 / k9, { n: 16, capEnd: false, turn: .3, capSteps: 3, color: (i, k, c) => (Math.floor(c[1] * 2.2) % 2 ? C.BARK : C.PLANK) });
  };
  const frond = (kit, f, count, sections, top) => {
    const a = f * 2 * PI / count + .2, droop = .8 + hash(f, 1042, 1) * .6, len = 3.3 + hash(f, 1042, 2) * .5;
    kit.group({ pos: top, rot: [0, -a, 0] }, () => kit.loft(Array.from({ length: sections }, (_, s) => {
      const t = s / (sections - 1), y = .55 * Math.sin(t * PI * .9) - droop * t * t * 1.8, w = Math.max(.06, .55 * Math.sin(PI * (.12 + t * .82)));
      // A V-folded frond: the midrib lower than the blade edges.
      return { z: t * len, points: OK.roundRect(w, .04, .04, { kArc: 4, kW: 2 }).map(([x, yy]) => [x, y + yy + .07 * (x / w) ** 2 * w]) };
    }), { capStart: false, capEnd: false, turn: sections > 6 ? .3 : .6, color: (s, e) => s % 2 ? TINT : TINT_LIGHT }));
  };
  organic('PalmTree', { smooth: 40, tint: '6FA05A', kind: 'tree', maxScale: 2 }, kit => {
    palmTrunk(kit, 9);
    const top = [1.3, 6.4, .1];
    for (let f = 0; f < 7; f++) frond(kit, f, 7, 8, top);
    for (let c = 0; c < 2; c++) { const a = c * 2.6 + .4; kit.blob(top[0] + Math.cos(a) * .35, top[1] - .35, top[2] + Math.sin(a) * .35, .24, .26, .24, { sub: 2, color: () => C.BARK_DARK }); }
  }, kit => {
    palmTrunk(kit, 4);
    const top = [1.3, 6.4, .1];
    for (let f = 0; f < 4; f++) frond(kit, f, 4, 5, top);
  });
  // Dead tree: a gnarled bent trunk splitting into bare limbs with broken
  // twigs and shelf fungus.
  organic('DeadTree', { smooth: 35, tint: 'B8A68A', kind: 'tree', maxScale: 2 }, kit => {
    trunk(kit, { h: 5.4, r0: .55, r1: .26, flare: .45, lobes: 4, seed: 1051, s: 2, top: false, bend: t => [.12 * Math.sin(t * PI * 1.5), .05 * Math.sin(t * PI)] });
    const limbs = [[[.05, 4.4, 0], [.9, 5.7, .25], [1.6, 7.0, .4], [1.85, 7.7, .35]], [[0, 4.9, 0], [-.55, 6.2, -.2], [-.95, 7.4, -.3]], [[.05, 5.1, 0], [.25, 6.6, .1], [.1, 7.6, 0]], [[-.1, 3.3, 0], [-.8, 3.9, .1], [-1.2, 4.8, .15]]];
    for (const l of limbs) limb(kit, l, .26, .07, C.BARK_DARK, { capEnd: true });
    for (const [p, q] of [[[1.25, 6.3, .3], [1.75, 6.5, -.2]], [[-.75, 6.8, -.25], [-1.2, 7.0, .2]], [[-1.0, 4.4, .1], [-1.35, 4.3, -.3]]]) limb(kit, [p, q], .09, .045, C.BARK_DARK, { capEnd: true });
    for (const [y, a] of [[1.6, .3], [2.4, 2.4], [3.1, 4.0]]) kit.group({ pos: [Math.cos(a) * .5, y, Math.sin(a) * .5], rot: [0, -a, 0] }, () =>
      lat(kit, P([[0, -.02], [.3, -.02], [.34, .05], [.22, .12], [0, .14]], [0, .03, .05, .06]), { n: 16, sz: .6, color: (l, i, c) => c[1] < .02 ? TINT_DARK : TINT }));
  }, kit => {
    ftrunk(kit, { h: 6.4, r0: .55, r1: .2, s: 2, bark: C.BARK_DARK, bend: t => [.12 * Math.sin(t * PI * 1.5), .05 * Math.sin(t * PI)] });
    limb(kit, [[.05, 4.4, 0], [.9, 5.7, .25], [1.6, 7.0, .4], [1.85, 7.7, .35]], .26, .07, C.BARK_DARK, { capEnd: true, turn: .6 });
    limb(kit, [[0, 4.9, 0], [-.55, 6.2, -.2], [-.95, 7.4, -.3]], .26, .07, C.BARK_DARK, { capEnd: true, turn: .6 });
  });

  // =========================================================================
  // Rocks, cliffs and the cavern stalactite.
  // =========================================================================
  organic('Boulder', { smooth: 50, kind: 'rock', maxScale: 2 }, kit => {
    lump(kit, { pos: [0, .95, 0], r: 2.2, hb: .95, ht: 1.6, sz: .86, seed: 101, amp: .07, freq: 1.2, s: 2, steps: 6, color: stoneField(101) });
  }, kit => {
    flump(kit, { pos: [0, .95, 0], r: 2.2, hb: .95, ht: 1.6, sz: .86, seed: 101, freq: 1.2, s: 2, color: stoneField(101) });
  });
  organic('RockCluster', { smooth: 50, kind: 'rock', maxScale: 2 }, kit => {
    lump(kit, { pos: [0, .75, 0], r: 1.9, hb: .75, ht: 1.5, sz: .9, seed: 111, amp: .07, s: 2, steps: 5, color: stoneField(111) });
    lump(kit, { pos: [1.9, .42, .7], r: 1.1, hb: .45, ht: .85, sz: .9, seed: 112, amp: .07, s: 2, steps: 4, color: stoneField(112) });
    lump(kit, { pos: [-1.6, .35, -.9], r: .9, hb: .35, ht: .7, seed: 113, amp: .07, s: 2, steps: 4, color: stoneField(113) });
    lump(kit, { pos: [.6, .2, -1.6], r: .6, hb: .2, ht: .45, sz: .9, seed: 114, amp: .07, s: 2, steps: 4, color: stoneField(114, false) });
  }, kit => {
    flump(kit, { pos: [0, .75, 0], r: 1.9, hb: .75, ht: 1.5, sz: .9, seed: 111, s: 2, color: stoneField(111) });
    flump(kit, { pos: [1.9, .42, .7], r: 1.1, hb: .45, ht: .85, sz: .9, seed: 112, s: 2, color: stoneField(112) });
  });
  // Columnar basalt: softened hexagonal columns with slanted mossy tops on a
  // low stony skirt (cliff dressing: SEG_FAR subdivision like the terrain cliffs).
  const basalt = (kit, columns, N, stepDeg, skirtN) => {
    columns.forEach(([x, z, h], i) => {
      const prof = P([[.62, -.4], [.64, h], [.3, h + .12], [0, h + .14]], [0, .2, .2], stepDeg, 3.2);
      lat(kit, prof, { n: N, phase: .25 + i,
        jitter: (l) => 1, wobble: () => [x, z],
        lift: (l, k) => Math.cos(k * 2 * PI / N + i) * .16 * sstep(h - 1.2, h + .1, prof[l][1]),
        color: (l, k, c) => c[1] > h - .15 ? (fbm([c[0], c[1], c[2]], 1.5, 120 + i, 2) > -.1 ? C.MOSS : C.STONE_LIGHT) : fbm([c[0] * 2, c[1] * .6, c[2] * 2], 1, 121, 2) > .3 ? C.STONE_DARK : C.STONE });
    });
    lump(kit, { pos: [0, -.1, 0], r: 3.4, hb: .5, ht: .9, sz: .88, seed: 122, amp: .07, s: 2, steps: skirtN > 16 ? 6 : 4, minSteps: skirtN > 16 ? 6 : 4, n: skirtN, color: stoneField(122) });
  };
  organic('CliffPiece', { smooth: 50, kind: 'rock', maxScale: 2, segFar: true }, kit => {
    basalt(kit, [[0, 0, 6.2], [1.15, .6, 5.1], [-1.1, .5, 5.6], [.05, -1.0, 4.6]], 20, 12, 20);
  }, kit => {
    basalt(kit, [[0, 0, 6.2], [1.15, .6, 5.1], [-1.1, .5, 5.6]], 16, 26, 16);
  });
  // Layered outcrop: three stepped strata stacks with mossy ledges and scree.
  const ledge = (kit, x, z, r, y0, h, yaw, seed, layers, far) => {
    for (let k = 0; k < layers; k++) {
      const rr = r * (1 - k * .2), yb = y0 + k * h;
      (far ? flump : lump)(kit, { pos: [x, yb + h * .45, z], rot: [0, yaw + k * .7, 0], r: rr * 1.05, hb: h * .5, ht: h * .55, sx: 1.25, seed: seed + k, amp: .07, freq: 1.1, s: 2, steps: 4,
        color: (c, up) => up > .55 ? (fbm([c[0], c[1], c[2]], 1.4, seed + k, 2) > -.15 ? C.MOSS : C.STONE_LIGHT) : up < -.3 ? C.STONE_DARK : Math.sin(c[1] * 5 + k) > .4 ? C.STONE_LIGHT : C.STONE });
    }
  };
  organic('RockOutcrop', { smooth: 50, kind: 'rock', maxScale: 2 }, kit => {
    ledge(kit, -.4, -.6, 2.6, -.3, 1.35, .2, 1001, 3);
    ledge(kit, 2.4, 1.6, 1.7, -.2, 1.1, 1.3, 1011, 2);
    ledge(kit, -2.4, 2.1, 1.3, -.2, .85, 2.1, 1021, 2);
  }, kit => {
    ledge(kit, -.4, -.6, 2.6, -.3, 1.35, .2, 1001, 2, true);
    ledge(kit, 2.4, 1.6, 1.7, -.2, 1.1, 1.3, 1011, 1, true);
    ledge(kit, -2.4, 2.1, 1.3, -.2, .85, 2.1, 1021, 1, true);
  });
  // Gloomhollow stalactite (1.8 x 7, hanging): drip cones with glowing tips,
  // rooted in a cavern-roof boss.
  const drip = (kit, x, z, top, len, r, seed, N = 20, stepDeg = 18, tip = 4) => {
    const prof = [...OK.bowl(r * .22, top - len * .9, len * .1, tip), ...P([[r * .22, top - len * .9], [r * .5, top - len * .6], [r * .85, top - len * .25], [r, top]], [0, len * .2, len * .2], stepDeg)];
    lat(kit, prof, { n: N, wobble: () => [x, z],
      jitter: (l, i) => 1 + .08 * fbm([Math.cos(i * 2 * PI / N), prof[l][1] * .5, Math.sin(i * 2 * PI / N)], 1.2, seed, 2),
      color: (l, i, c) => c[1] < top - len * .82 ? TINT_LIGHT : c[1] < top - len * .62 ? TINT : fbm([c[0] * 2, c[1] * .5, c[2] * 2], 1, seed + 1, 2) > .25 ? C.STONE_DARK : C.SLATE });
  };
  organic('Stalactite', { smooth: 50, tint: 'B59CFF', kind: 'rock', maxScale: 2 }, kit => {
    drip(kit, 0, 0, 7, 7, .9, 951);
    drip(kit, .55, .3, 7, 3.2, .38, 952);
    drip(kit, -.5, -.35, 7, 4.1, .42, 953);
    drip(kit, .1, -.6, 7, 2.2, .3, 954);
    lump(kit, { pos: [0, 6.75, 0], r: 1.0, hb: .3, ht: .3, seed: 955, amp: .07, s: 2, steps: 4, color: stoneField(955, false) });
  }, kit => {
    drip(kit, 0, 0, 7, 7, .9, 951, 16, 24, 4);
    drip(kit, -.5, -.35, 7, 4.1, .42, 953, 16, 24, 4);
    flump(kit, { pos: [0, 6.75, 0], r: 1.0, hb: .3, ht: .3, seed: 955, s: 2, color: stoneField(955, false) });
  });

  // =========================================================================
  // Ore veins per tier: soft-cut tinted crystal clusters in a mossy rock bed.
  // Tier 1 copper/aetherite, 2 brassite/sunsteel, 3 voidstone/starmetal, 4 prismite/celestium.
  // =========================================================================
  const rockBed = (kit, rx, ry, rz, seed, far) => (far ? flump : lump)(kit, { pos: [0, ry * .35, 0], r: rx, hb: ry * .35, ht: ry, sz: rz / rx, seed, amp: .07, s: 1.5, steps: 5, color: stoneField(seed) });
  const ore = (name, tint, bed, y, list, extra, farCount) => organic(name, { smooth: 50, tint, kind: 'ore', maxScale: 1.5 }, kit => {
    rockBed(kit, ...bed);
    for (const [x, z, rx, rz, len, r, s] of list) crystal(kit, { pos: [x, y, z], rot: [rx, 0, rz], len, r, seed: s, s: 1.5 });
    if (extra) extra(kit);
  }, kit => {
    rockBed(kit, ...bed, true);
    for (const [x, z, rx, rz, len, r, s] of list.slice(0, farCount)) fcrystal(kit, { pos: [x, y, z], rot: [rx, 0, rz], len, r: r * 1.15, seed: s, s: 1.5 });
  });
  ore('OreVein1', 'B87333', [1.9, 1.0, 1.6, 131], .6, [[.1, 0, .1, -.15, 1.5, .26, 1], [.7, .4, .3, -.6, 1.0, .2, 2], [-.6, .3, .35, .55, 1.1, .2, 3]], null, 2);
  ore('OreVein2', 'D4A84B', [2.3, 1.3, 2.0, 141], .95, [[0, 0, 0, 0, 2.2, .34, 1], [.9, .4, .2, -.55, 1.5, .26, 2], [-.85, .35, .3, .55, 1.6, .26, 3], [.3, -.8, -.6, -.2, 1.3, .22, 4], [-.4, -.7, -.5, .35, 1.1, .2, 5]], null, 3);
  ore('OreVein3', '5B3F8C', [2.6, 1.4, 2.3, 151], 1.0, [[0, 0, 0, .05, 3.0, .44, 1], [1.1, .5, .2, -.5, 2.0, .32, 2], [-1.1, .4, .25, .5, 2.2, .32, 3], [.4, -1.0, -.55, -.2, 1.8, .3, 4], [-.6, -.9, -.5, .35, 1.5, .26, 5], [1.3, -.6, -.3, -.7, 1.2, .22, 6], [-1.5, -.2, 0, .8, 1.1, .22, 7]], kit => {
    // A floating halo ring of light around the cluster.
    kit.tube(Array.from({ length: 24 }, (_, i) => { const a = i * 2 * PI / 24; return [Math.cos(a) * 1.6, 1.25 + .1 * Math.sin(3 * a), Math.sin(a) * 1.6]; }), .08, { n: 16, closed: true, color: TINT_LIGHT });
  }, 3);
  ore('OreVein4', 'E86FB8', [3.0, 1.5, 2.7, 161], 1.05, [[0, 0, 0, 0, 4.2, .58, 1], [1.3, .6, .2, -.45, 2.6, .38, 2], [-1.3, .5, .25, .45, 2.8, .38, 3], [.5, -1.2, -.5, -.2, 2.3, .34, 4], [-.7, -1.1, -.45, .3, 2.0, .3, 5], [1.6, -.7, -.3, -.65, 1.6, .26, 6], [-1.8, -.3, 0, .75, 1.5, .26, 7]], kit => {
    // Orbiting shard motes above the crown.
    for (let i = 0; i < 3; i++) { const a = i * 2 * PI / 3 + .3, y = 4.0 + (i % 2) * .5; lat(kit, OK.ellipsoid(.18, y - .05, .37, .47, 4), { n: 16, wobble: () => [Math.cos(a) * 2.0, Math.sin(a) * 2.0], color: () => i % 2 ? TINT_LIGHT : C.GLINT }); }
  }, 3);

  // =========================================================================
  // Crops (a rounded soil mound with furrow ridges + plants). Tint = produce.
  // =========================================================================
  // The soil bed (3 x .44 x 2.2): a rounded loaf of tilled soil, darker at the
  // foot, lofted along local Z and turned to run along X.
  const soilBed = (kit, far) => kit.group({ rot: [0, PI / 2, 0] }, () => kit.loft((far ? [0, 2, 4] : [0, 1, 2, 3, 4]).map(s => {
    const t = s / 4, x = -1.5 + 3 * t, k = Math.sin(t * PI) ** .25;
    // A soft loaf: the top domes a little between the two planting rows.
    return { z: x, points: OK.roundRect(1.1 * (.94 + .06 * k), .22 * (.9 + .1 * k), .16, { kArc: 4, kW: far ? 3 : 4, kH: 1 }).map(([z, y]) => [z, .22 + y + (y > 0 ? .03 * (1 - (z / 1.1) ** 2) : 0)]) };
  }), { capSteps: far ? 3 : 4, color: (s, e) => C.SOIL }));
  const glowcap = (kit, x, z, s, i, far) => kit.group({ pos: [x, .36, z], scale: s, rot: [0, i, (hash(i, 181, 1) - .5) * .3] }, () => {
    // The stem: a tapering tube from the soil into the cap.
    limb(kit, [[0, -.05, 0], [0, .5, 0], [0, 1.0, 0]], .17, .12, C.CLOTH, { turn: .6 });
    // A glowing cap with a rounded rim and luminous gill spots on top.
    lat(kit, OK.capProfile(.12, .62, .96, .07, .5, far ? 3 : 4, far ? 30 : 22), { n: far ? 16 : 20, color: (l, k, c) => c[1] < 1.0 ? TINT_DARK : fbm([c[0] * 4, c[1] * 4, c[2] * 4], 1, 181 + i, 2) > .35 ? C.GLINT : TINT });
  });
  organic('CropGlowcap', { smooth: 50, tint: 'F4A261', kind: 'crop', maxScale: 1.2 }, kit => {
    soilBed(kit);
    for (const [x, z, s, i] of [[-.8, -.4, 1.1, 0], [.35, -.5, .8, 1], [.9, .45, 1.0, 2], [-.4, .5, .75, 3]]) glowcap(kit, x, z, s, i);
  }, kit => {
    soilBed(kit, true);
    for (const [x, z, s, i] of [[-.8, -.4, 1.1, 0], [.9, .45, 1.0, 2]]) glowcap(kit, x, z, s, i, true);
  });
  const bloom = (kit, x, z, h, i, far) => {
    limb(kit, [[x, .3, z], [x + .1, .4 + h * .6, z], [x, .4 + h, z]], .05, .04, C.LEAF, { turn: far ? .6 : .3 });
    if (false) kit.group({ pos: [x, .55, z], rot: [0, i, .95] }, () => kit.loft([0, 1, 2, 3].map(s => {
      const t = s / 3, w = .13 * Math.sin(PI * (.12 + .8 * t)) + .03; return { z: t * .65, points: OK.roundRect(w, .015, .015, { kArc: 4, kW: 2 }).map(([a, b]) => [a, b - .2 * t * t]) };
    }), { capStart: false, capEnd: false, color: () => C.LEAF }));
    // The bloom: a six-lobed petal cup (scalloped capProfile) round a flame heart.
    const N = far ? 18 : 24;
    kit.group({ pos: [x, .4 + h, z], rot: [.3, i, 0] }, () => {
      lat(kit, OK.capProfile(.05, .42, -.02, .05, .12, far ? 3 : 4, far ? 30 : 18).map(([r, y]) => [r, -y + .1]).reverse(), { n: N,
        jitter: (l, k) => 1 + .06 * Math.cos(6 * k * 2 * PI / N), color: (l, k, c) => Math.hypot(c[0], c[2]) < .12 ? C.FLAME : Math.cos(6 * Math.atan2(c[2], c[0])) > .3 ? TINT_LIGHT : TINT });
    });
  };
  organic('CropBloom', { smooth: 50, tint: 'B8C0FF', kind: 'crop', maxScale: 1.2 }, kit => {
    soilBed(kit);
    for (const [x, z, h, i] of [[-.85, -.4, 1.6, 0], [.95, .45, 1.8, 2], [-.1, .5, 1.3, 3]]) bloom(kit, x, z, h, i);
  }, kit => {
    soilBed(kit, true);
    for (const [x, z, h, i] of [[-.85, -.4, 1.6, 0], [.95, .45, 1.8, 2]]) bloom(kit, x, z, h, i, true);
  });
  const berries = (c, up) => fbm([c[0] * 3.2, c[1] * 3.2, c[2] * 3.2], 1, 193, 2) > .38 && up > -.3 ? TINT : up > .4 ? C.LEAF : fbm([c[0], c[1], c[2]], 1.2, 191, 2) > .1 ? C.LEAF_DARK : C.LEAF;
  organic('CropBush', { smooth: 50, tint: 'FFE66D', kind: 'crop', maxScale: 1.2, sphere: [[.1, 1.1, 0, 1.4, .5]] }, kit => {
    soilBed(kit);
    lump(kit, { pos: [-.4, 1.05, 0], r: 1.0, hb: .6, ht: .8, sz: .9, seed: 191, amp: .07, s: 1.2, steps: 5, color: berries });
    lump(kit, { pos: [.6, .95, .1], r: .85, hb: .5, ht: .68, sz: .94, seed: 192, amp: .07, s: 1.2, steps: 4, color: berries });
  }, kit => {
    soilBed(kit, true);
    flump(kit, { pos: [.05, 1.0, 0], r: 1.4, hb: .65, ht: .8, sz: .7, seed: 191, s: 1.2, color: berries });
  });
  // Shrub (2.6 cube slot, sunk 0.4 into the ground): clustered leafy mounds
  // with painted berries.
  organic('Bush', { smooth: 50, tint: '6C9A58', kind: 'plant', maxScale: 1.6, sphere: [[0, 1.4, 0, 1.6, .55]] }, kit => {
    lump(kit, { pos: [0, 1.1, 0], r: 1.25, hb: .7, ht: .95, sz: .96, seed: 991, amp: .07, s: 1.6, color: leaves(991, C.ROSE, .55) });
    lump(kit, { pos: [.6, 1.5, .35], r: .75, hb: .5, ht: .65, seed: 992, amp: .07, s: 1.6, steps: 4, color: leaves(992, C.ROSE, .55) });
    lump(kit, { pos: [-.55, 1.55, -.3], r: .7, hb: .5, ht: .7, seed: 993, amp: .07, s: 1.6, steps: 4, color: leaves(993, C.ROSE, .55) });
    lump(kit, { pos: [.05, 2.0, -.05], r: .55, hb: .45, ht: .55, seed: 994, amp: .07, s: 1.6, steps: 4, color: leaves(994, C.ROSE, .55) });
  }, kit => {
    flump(kit, { pos: [0, 1.2, 0], r: 1.35, hb: .8, ht: 1.25, sz: .96, seed: 991, s: 1.6, color: leaves(991, C.ROSE, .55) });
  });
  // Wildflower patch (grove decor): a low mossy mound with six stems and
  // four-petal blooms round amber hearts.
  const flower = (kit, k, far) => {
    const a = k * 2.4, d = .35 + (k % 3) * .5, x = Math.cos(a) * d, z = Math.sin(a) * d, h = .55 + hash(k, 1, 531) * .5;
    limb(kit, [[x, .1, z], [x + .05, h * .6, z], [x, h, z]], .04, .035, C.LEAF_DARK, { turn: .5 });
    const N = far ? 16 : 16;
    kit.group({ pos: [x, h - .02, z], rot: [(hash(k, 2, 531) - .5) * .4, a, 0] }, () => lat(kit, OK.capProfile(.03, .26, 0, .04, .05, far ? 3 : 4, far ? 30 : 24), { n: N,
      jitter: (l, i) => 1 + .07 * Math.cos(4 * i * 2 * PI / N), color: (l, i, c) => Math.hypot(c[0], c[2]) < .07 && c[1] > .02 ? C.AMBER : k % 3 === 0 ? TINT_LIGHT : TINT }));
  };
  organic('FlowerPatch', { smooth: 50, tint: 'D67D6A', kind: 'plant', maxScale: 1.6 }, kit => {
    lump(kit, { pos: [0, 0, 0], r: 1.9, hb: .15, ht: .28, seed: 530, amp: .04, s: 1.6, steps: 8, color: (c, up) => up > .55 ? C.LEAF : C.LEAF_DARK });
    for (let k = 0; k < 5; k++) flower(kit, k);
  }, kit => {
    flump(kit, { pos: [0, 0, 0], r: 1.9, hb: .15, ht: .28, amp: .04, seed: 530, s: 1.6, steps: 5, color: (c, up) => up > .55 ? C.LEAF : C.LEAF_DARK });
    for (let k = 0; k < 2; k++) flower(kit, k * 3, true);
  });
  // Glowshroom cluster: five pale stems under domed glowing caps with rounded
  // rims and bright spots.
  const shroom = (kit, [x, z, h, r], k, far) => {
    limb(kit, [[x, -.05, z], [x + .1 * (k % 2 ? 1 : -1), h * .5, z], [x, h, z]], r * .26, r * .2, C.CLOTH, { turn: far ? .6 : .3 });
    kit.group({ pos: [x, 0, z] }, () => lat(kit, OK.capProfile(r * .2, r, h - .1, r * .12, r * .6, far ? 3 : 5, far ? 30 : 18), { n: far ? 16 : segs(r, 1.6, 20), phase: k,
      color: (l, i, c) => c[1] < h - .02 ? TINT_DARK : fbm([c[0] * 3, c[1] * 3, c[2] * 3], 1, 550 + k, 2) > .4 ? TINT_LIGHT : TINT }));
  };
  const SHROOMS = [[0, 0, 2.6, 1.3], [1.1, .4, 1.7, .9], [-.9, .5, 1.4, .75], [.4, -1.0, 1.1, .6], [-.4, -.7, .8, .45]];
  organic('Glowshroom', { smooth: 50, tint: '7FD3C4', kind: 'plant', maxScale: 1.6 }, kit => {
    SHROOMS.forEach((c, k) => shroom(kit, c, k));
  }, kit => {
    SHROOMS.slice(0, 3).forEach((c, k) => shroom(kit, c, k, true));
  });
  // Sea coral fan: a stony base with seven branching soft arms.
  const coral = (kit, k, twigs, turn) => {
    const a = -1.1 + k * .37, len = 1.6 + hash(k, 1, 561) * 1.0;
    const tip = [Math.sin(a) * len, .3 + Math.cos(a) * len * 1.2, (hash(k, 2, 561) - .5) * .4], mid = [tip[0] * .5, tip[1] * .55, tip[2]];
    limb(kit, [[0, .2, 0], mid, tip], .16, .06, TINT, { capEnd: true, turn, color: (i, j, c) => c[1] > tip[1] * .8 ? TINT_LIGHT : TINT });
    if (twigs) limb(kit, [mid, [mid[0] + .35 * (k % 2 ? 1 : -1), tip[1] * .75, mid[2] + .1]], .08, .045, TINT_LIGHT, { capEnd: true, turn });
  };
  organic('CoralFan', { smooth: 50, tint: 'E76F7B', kind: 'plant', maxScale: 1.6 }, kit => {
    lump(kit, { pos: [0, 0, 0], r: 1.2, hb: .2, ht: .4, sz: .84, seed: 560, amp: .07, s: 1.6, steps: 4, color: () => C.STONE_LIGHT });
    for (let k = 0; k < 7; k++) coral(kit, k, true, .2);
  }, kit => {
    flump(kit, { pos: [0, 0, 0], r: 1.2, hb: .2, ht: .4, sz: .84, seed: 560, s: 1.6, steps: 5, color: () => C.STONE_LIGHT });
    for (let k = 1; k < 7; k += 2) coral(kit, k, false, .35);
  });

  // =========================================================================
  // §42 depleted node variants (client-local mesh slots). Uniform fit.
  // =========================================================================
  // Tree stump: a sawn trunk with growth rings on the cut and flared roots.
  const stump = (kit, N, stepDeg) => {
    const prof = P([[0, -.1], [.95, -.1], [.92, .1], [.72, .4], [.64, 1.0], [.62, 1.16], [.5, 1.2], [0, 1.2]], [0, .1, .2, .3, .1, .05, 0], stepDeg);
    lat(kit, prof, { n: N,
      jitter: (l, i) => 1 + .12 * sstep(.5, -.1, prof[l][1]) * (1 + Math.cos(5 * i * 2 * PI / N + 1)) / 2 + .02 * fbm([Math.cos(i * 2 * PI / N), prof[l][1], Math.sin(i * 2 * PI / N)], 1.5, 1201, 2),
      color: (l, i, c) => c[1] > 1.17 ? (Math.floor(Math.hypot(c[0], c[2]) * 9) % 2 ? C.PLANK : C.STRAW) : c[1] < .15 ? TINT_DARK : fbm([c[0] * 2, c[1] * .5, c[2] * 2], 1, 1202, 2) > .2 ? TINT_DARK : TINT });
  };
  organic('TreeStump', { smooth: 50, tint: '7A5638', kind: 'node', maxScale: 1.5 }, kit => stump(kit, 28, 18), kit => stump(kit, 20, 32));
  // Depleted rock: the vein's boulder with its crystals gone, plain grey stone.
  organic('DepletedRock', { smooth: 50, tint: '767A80', kind: 'node', maxScale: 1.5 }, kit => {
    lump(kit, { pos: [0, .45, 0], r: 1.6, hb: .45, ht: .75, sz: .85, seed: 1211, amp: .07, s: 1.5, color: stoneField(1211, false, true) });
    for (let k = 0; k < 3; k++) { const a = k * 2.1 + .2, r = 1.8 + hash(k, 1213, 1) * .3; lump(kit, { pos: [Math.cos(a) * r, .08, Math.sin(a) * r], r: .25, hb: .08, ht: .16, seed: 1214 + k, amp: .07, s: 1.5, steps: 3, n: 16, color: () => TINT_DARK }); }
  }, kit => {
    flump(kit, { pos: [0, .45, 0], r: 1.6, hb: .45, ht: .75, sz: .85, seed: 1211, s: 1.5, color: stoneField(1211, false, true) });
  });
  // Tilled soil: a bare bed of three furrows (the crop harvested).
  const tilled = (kit, sections, kW, furrows, capSteps) => kit.loft(sections.map(q => {
    const t = q / 4, x = -1.95 + 3.9 * t, k = Math.sin(t * PI) ** .3;
    // A rounded bed lofted along X; its top rises and falls in furrows along Z.
    return { z: x, points: OK.roundRect(1.9 * (.92 + .08 * k), .16 * (.85 + .15 * k), .12, { kArc: 4, kW, kH: 1 }).map(([z, y]) => [z, .16 + y + (furrows && y > 0 ? .02 * Math.cos(z * PI / .95) * sstep(1.75, 1.3, Math.abs(z)) : 0)]) };
  }), { capSteps, color: (sq, e) => TINT });
  organic('TilledSoil', { smooth: 50, tint: '5C422C', kind: 'node', maxScale: 1.5 }, kit => tilled(kit, [0, 2, 4], 12, true, 4), kit => tilled(kit, [0, 2, 4], 3, false, 3));
};
