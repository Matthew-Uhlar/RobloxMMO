// World Art & Regions (docs/DEPTH-CONTRACT.md §30): island hulls, bridges,
// landmarks and the richer prop kit. Loaded by art/generate-props.cjs after
// art/world-shapes.cjs; every shape is authored here from primitives with the
// deterministic hash (no Math.random, no imported assets). Units are studs at
// scale 1, +Y up, fronts face -Z. Extra meta used by the forge:
//   range: studs within which this mesh is forged (island hulls and landmarks are
//          seen from far away, so they forge beyond the default prop radius)
'use strict';
module.exports = ({ world, C, PI, hash }) => {
  const { TINT, TINT_DARK, TINT_LIGHT } = C;
  const wave = (seed, amount) => (level, i) => 1 + (hash(level, i, seed) - .5) * 2 * amount;

  // -------------------------------------------------------------------------
  // Island hulls. Cliffs ride the island's "Floating foundation" cylinder
  // (fit box = that cylinder: radius 10, 6 tall, top at 0) and keels ride the
  // "Island underside" cylinder below it (radius 10, 10 deep). Both stretch
  // with the island, so strata depth grows with the island's size.
  // -------------------------------------------------------------------------
  const CLIFF_FIT = [[-10, -6, -10], [10, 0, 10]];
  // §54 QC (A2-A5): the catalog hulls are the far LOD (and the Sky Chart's) of
  // terrain.client.lua's per-island hull. The foundation is now a thick wall
  // (clamp(R*0.18, 10, 30) studs, world.server.lua), so the fit box stretches
  // about 3.4x more radially than vertically on every island; the profiles are
  // authored for that and checked by the generator at the smallest and largest
  // island (normal deviation <= 20 deg, chord error <= 0.15 studs: 80 segments).
  // Colours follow continuous strata bands of height.
  const HULL_N = 80;
  const strataField = (lip) => (level, i, c) => {
    if (c[1] > -.25) return lip ? C.SOIL : TINT_LIGHT;
    const band = Math.sin(-c[1] * 2.2 + Math.atan2(c[2], c[0]) * .5);
    return c[1] < -5.4 ? TINT_DARK : band > .45 ? TINT_LIGHT : band < -.45 ? TINT_DARK : TINT;
  };
  // Wall radius at depth t (0 top .. 1 bottom): an overhanging rim, four soft
  // strata ledges, a gentle tuck toward the keel.
  const wallRadius = t => 10.12 + .07 * Math.exp(-(((t - .04) / .05) ** 2)) + .035 * Math.sin(2 * PI * 4 * t) * (1 - t * .6) - .55 * Math.max(0, t - .8) ** 2 / .04;
  const cliffWall = (kit, seed, lip) => {
    const levels = [];
    for (let k = 0; k <= 28; k++) { const t = k / 28; levels.push([wallRadius(t), -6 * t]); }
    kit.lathe(levels, {
      n: HULL_N, phase: hash(seed, 1, 2),
      jitter: (level, i) => 1 + .006 * Math.sin(5 * i * 2 * PI / HULL_N + seed + level * .2),
      color: strataField(lip),
    });
  };
  world('IslandCliff', { smooth: 45, tint: '6B7380', fit: CLIFF_FIT, kind: 'rock', range: 1400, hull: true, blend: [C.SOIL] }, kit => {
    cliffWall(kit, 401, true);
    // Grass lip: a rounded turf curb rolling over the rim (meadow top = fit top + 0.3 x the wall scale).
    const lipPts = [];
    for (let k = 0; k <= 8; k++) { const a = PI / 2 - k * PI / 8; lipPts.push([10.12 + .1 * Math.cos(a), .04 + .06 * Math.sin(a)]); }
    kit.lathe(lipPts, {
      n: HULL_N, phase: .05, jitter: (level, i) => 1 + .004 * Math.sin(7 * i * 2 * PI / HULL_N + level),
      color: (l, i, c) => c[1] > .07 ? C.LEAF : c[1] > .02 ? C.MOSS : C.LEAF_DARK,
    });
  });
  world('IslandCliffBare', { smooth: 45, tint: '5E6470', fit: CLIFF_FIT, kind: 'rock', range: 1400, hull: true }, kit => {
    cliffWall(kit, 411, false);
    // Weathered crown: a low rounded rubble ring on the rim.
    const crown = [];
    for (let k = 0; k <= 8; k++) { const a = PI / 2 - k * PI / 8; crown.push([10.1 + .1 * Math.cos(a), .03 + .06 * Math.sin(a)]); }
    kit.lathe(crown, { n: HULL_N, jitter: (level, i) => 1 + .006 * Math.sin(9 * i * 2 * PI / HULL_N), color: (l, i, c) => c[1] > .05 ? TINT_LIGHT : TINT });
  });
  // Keels: strata tapering into a hanging spire (unit: radius 10, top at 0, tip at -10).
  const keelBody = (kit, seed, band, lobes = 5) => {
    const levels = [];
    for (let k = 0; k <= 24; k++) { const t = k / 24; levels.push([k === 24 ? 0 : 10 * Math.cos(t * PI / 2) ** 1.25 * (1 - .04 * Math.sin(t * 9)), -10 * t]); }
    kit.lathe(levels, {
      n: HULL_N, phase: hash(seed, 2, 1),
      jitter: (level, i) => 1 + .035 * Math.sin(3 * i * 2 * PI / HULL_N + seed) * Math.min(1, level / 6),
      wobble: (level) => level > 14 ? [Math.cos(seed) * (level - 14) * .08, Math.sin(seed) * (level - 14) * .06] : [0, 0],
      color: band,
    });
    for (let k = 0; k < lobes; k++) {
      const a = k * 2 * PI / lobes + hash(k, 1, seed) * .5, d = 5.2 + hash(k, 2, seed) * 2.2, top = -1.8 - hash(k, 3, seed) * 1.2;
      const len = 2.6 + hash(k, 4, seed) * 3.0, w = 1.0 + hash(k, 5, seed) * .7, lv = [];
      for (let j = 0; j <= 8; j++) { const t = j / 8; lv.push([j === 8 ? 0 : w * Math.cos(t * PI / 2) ** 1.2, .4 - (len + .4) * t]); }
      kit.group({ pos: [Math.cos(a) * d, top, Math.sin(a) * d] }, () => kit.lathe(lv, { n: 32, phase: k, color: band }));
    }
  };
  const strata = () => (level, i, c) => c[1] > -.6 ? C.SOIL
    : (Math.sin(-c[1] * 1.6) > .4 ? TINT_LIGHT : Math.sin(-c[1] * 1.6) < -.4 ? TINT_DARK : TINT);
  world('IslandKeel', { smooth: 45, tint: '5C6573', kind: 'rock', range: 1400, hull: true, blend: [C.SOIL] }, kit => keelBody(kit, 421, strata()));
  world('IslandKeelCrystal', { smooth: 45, tint: '424659', kind: 'rock', range: 1400, hull: true, blend: [C.SOIL] }, kit => {
    keelBody(kit, 431, strata(), 3);
    for (let k = 0; k < 7; k++) {
      const a = k * 2 * PI / 7 + hash(k, 1, 432), d = 2.5 + hash(k, 2, 432) * 5, y = -1.5 - (1 - d / 9) * 6 - hash(k, 3, 432) * 1.5;
      const len = 2.4 + hash(k, 6, 432) * 1.6;
      kit.group({ pos: [Math.cos(a) * d, y, Math.sin(a) * d], rot: [PI + (hash(k, 4, 432) - .5) * .6, a, (hash(k, 5, 432) - .5) * .6] }, () =>
        kit.lathe([[.4, -.3], [.52, .6], [.5, 1.3], [.36, 1.9], [.18, len - .2], [0, len]], { n: 24, phase: k, color: (l, i, c) => c[1] > 1.4 ? C.MINT : C.LAVENDER }));
    }
  });
  world('IslandKeelEmber', { smooth: 45, tint: '3B3236', kind: 'rock', range: 1400, hull: true, blend: [C.SOIL] }, kit => {
    keelBody(kit, 441, (level, i, c) => Math.sin(-c[1] * 1.6 + 1) > .75 ? C.EMBER : strata()(level, i, c));
    // Glowing magma seams: drips of ember running down the strata.
    for (let k = 0; k < 6; k++) {
      const a = k * 2 * PI / 6 + hash(k, 1, 442) * .4, d = 6.6 + hash(k, 2, 442) * 1.8, y = -1.6 - hash(k, 3, 442) * 2.4;
      kit.group({ pos: [Math.cos(a) * d, y, Math.sin(a) * d] }, () =>
        kit.lathe([[.3, .9], [.33, .1], [.28, -.6], [.18, -1.2], [.08, -1.55], [0, -1.7]], { n: 24, phase: k, color: (level) => level >= 3 ? C.FLAME : C.EMBER }));
    }
  });

  // -------------------------------------------------------------------------
  // Bridges: one mesh per span on an invisible slot box over the collider deck
  // (deck top at y 0, 8.4 wide, 40 long; the forge stretches the length).
  // Planks and paving sit 0.05 above the deck, so the dark primitive deck
  // reads as the shadow between them.
  // -------------------------------------------------------------------------
  const L = 20; // half length
  world('RopeBridge', { smooth: 30, fit: [[-4.2, -1, -L], [4.2, 3.6, L]], kind: 'bridge', range: 700 }, kit => {
    for (let i = 0; i < 34; i++) {
      const z = -L + .7 + i * (2 * L - 1.4) / 33, w = 6.6 + (hash(i, 1, 451) - .5) * .4;
      kit.box((hash(i, 2, 451) - .5) * .15, .13, z, w, .16, .95, i % 5 === 2 ? C.BARK : C.PLANK, (hash(i, 3, 451) - .5) * .03);
    }
    // Stringers under the plank ends, and the two sagging rope handrails.
    const sag = (t, depth) => -depth * (1 - (2 * t - 1) ** 2);
    for (const s of [-1, 1]) {
      kit.box(s * 3.1, -.35, 0, .36, .5, 2 * L, C.BARK_DARK);
      const rail = [], low = [];
      for (let k = 0; k <= 12; k++) { const t = k / 12, z = -L + 2 * L * t; rail.push([s * 3.8, 3.1 + sag(t, 1.1), z]); low.push([s * 3.75, 1.4 + sag(t, .45), z]) }
      kit.tube(rail, .13, { n: 4, color: C.STRAW });
      kit.tube(low, .09, { n: 4, color: C.STRAW });
      for (let k = 1; k < 12; k += 1) { const t = k / 12; kit.tube([[s * 3.8, 3.05 + sag(t, 1.1), -L + 2 * L * t], [s * 3.3, .2, -L + 2 * L * t]], [.05, .05], { n: 3, color: C.STRAW }) }
      for (const z of [-L + .5, L - .5]) {
        kit.group({ pos: [s * 3.9, 0, z] }, () => kit.lathe([[.3, -1], [.28, 2.95], [.36, 3.05], [.22, 3.35], [0, 3.6]], { n: 6, capStart: true, color: l => l >= 2 ? C.BRASS : C.BARK }));
      }
    }
  });
  world('StoneArchBridge', { smooth: 25, fit: [[-4.2, -3.4, -L], [4.2, 3.4, L]], kind: 'bridge', range: 700 }, kit => {
    // Paving courses.
    for (let i = 0; i < 16; i++) {
      const z = -L + 1.25 + i * 2.5;
      kit.box(0, .1, z, 6.9, .1, 2.42, i % 2 ? C.STONE_LIGHT : C.MARBLE);
    }
    // Arch under-structure: a pier at each end and a shallow arch ring between.
    kit.group({ rot: [0, PI / 2, 0] }, () => {
      const outline = [];
      for (let k = 0; k <= 12; k++) { const t = k / 12, z = -L + 2 * L * t; outline.push([z, -.25]) }
      for (let k = 12; k >= 0; k--) { const t = k / 12, z = -L + 2 * L * t; outline.push([z, -.9 - 2.5 * (2 * t - 1) ** 4]) }
      kit.prism(outline.reverse(), 7.6, C.STONE, C.STONE_DARK);
    });
    for (const s of [-1, 1]) {
      // Balustrade: plinth, balusters, handrail.
      kit.box(s * 3.85, .35, 0, .5, .5, 2 * L, C.STONE);
      kit.bevelBox(s * 3.85, 2.55, 0, .62, .22, 2 * L, .06, { top: C.MARBLE, side: C.STONE_LIGHT, bevel: C.MARBLE, bottom: C.STONE });
      for (let i = 0; i < 16; i++) kit.group({ pos: [s * 3.85, 0, -L + 1.6 + i * (2 * L - 3.2) / 15] }, () =>
        kit.lathe([[.2, .6], [.13, 1.3], [.22, 1.9], [.14, 2.45]], { n: 4, phase: PI / 4, color: l => l === 1 ? C.MARBLE : C.STONE_LIGHT }));
      for (const z of [-L + .4, 0, L - .4]) {
        kit.box(s * 3.85, 1.5, z, .8, 3.0, .8, C.STONE_LIGHT);
        kit.group({ pos: [s * 3.85, 0, z] }, () => kit.lathe([[.3, 3.0], [.34, 3.15], [.16, 3.3], [0, 3.4]], { n: 6, color: C.BRASS, capStart: true }));
      }
    }
    // Keystone medallions on the arch faces.
    for (const s of [-1, 1]) kit.jewel(s * 3.82, -1.0, 0, .12, .5, .5, C.BRASS);
  });
  world('CrystalBridge', { smooth: 20, tint: 'B59CFF', fit: [[-4.2, -1.6, -L], [4.2, 3.8, L]], kind: 'bridge', range: 700 }, kit => {
    for (let i = 0; i < 20; i++) {
      const z = -L + 1 + i * 2;
      kit.group({ pos: [0, .05, z] }, () => kit.lathe([[3.4, 0], [3.4, .12], [3.1, .16]], { n: 6, phase: PI / 6, sz: .32, capStart: true, capEnd: true, color: l => l === 1 ? TINT_LIGHT : C.GLASS }));
    }
    kit.box(0, -.6, 0, .5, .4, 2 * L, TINT_DARK);
    for (const s of [-1, 1]) {
      kit.box(s * 3.75, 2.6, 0, .14, .14, 2 * L - 1, TINT_LIGHT);
      for (let i = 0; i < 6; i++) {
        const z = -L + 1.5 + i * (2 * L - 3) / 5;
        kit.group({ pos: [s * 3.75, 0, z], rot: [0, i * .7, (hash(i, s + 2, 461) - .5) * .12] }, () =>
          kit.lathe([[.38, -1.4], [.48, 0], [.42, 2.6], [0, 3.8]], { n: 5, capStart: true, color: (l, k) => k % 2 ? TINT : TINT_LIGHT }));
        kit.jewel(s * 3.75, -1.0, z, .2, .45, .2, C.GLINT);
      }
    }
    for (const z of [-L + .3, L - .3]) kit.group({ pos: [0, 0, z] }, () => kit.ring(3.7, .28, .28, TINT_LIGHT, 12, 0, 0, PI, 0));
  });

  // -------------------------------------------------------------------------
  // Landmarks (one per region; kind 'tower' so verify-world checks they stand).
  // -------------------------------------------------------------------------
  world('Windmill', { smooth: 30, tint: 'C9A24E', kind: 'tower', range: 1200 }, kit => {
    // Stone foot, tapering timber tower, gallery and a thatched cap.
    kit.lathe([[5.2, 0], [5.0, 3.2], [4.7, 3.6]], { n: 10, capStart: true, color: (l, i) => l === 0 ? (i % 2 ? C.STONE : C.STONE_LIGHT) : C.STONE_DARK, jitter: wave(471, .03) });
    kit.lathe([[4.4, 3.5], [3.9, 9], [3.4, 14.5], [3.5, 15]], { n: 10, color: (l, i) => l === 1 ? C.PLANK : (i % 2 ? C.PLANK : C.BARK) });
    kit.ring(4.1, .35, .5, C.BARK, 14, PI / 2, 0, PI * 2, 9);
    kit.lathe([[4.3, 15], [4.4, 15.3], [3.6, 17.8], [1.4, 19.6], [0, 20.4]], { n: 10, capStart: true, color: (l, i) => l <= 1 ? C.BARK : (i % 2 ? TINT : TINT_DARK) });
    kit.lathe([[5.0, 14.8], [5.1, 15.1]], { n: 10, capStart: true, capEnd: true, color: C.BARK });
    // Door, windows, the sail shaft housing.
    kit.bevelBox(0, 1.9, -4.95, 1.9, 3.2, .4, .1, { top: C.BARK, side: C.BARK_DARK, bevel: C.BRASS, bottom: C.BARK, front: C.BARK_DARK });
    for (const [y, a] of [[7, .6], [11.5, -.5], [7.5, PI + .4]]) kit.group({ rot: [0, a, 0] }, () => kit.bevelBox(0, y, -3.95 + (y - 7) * .09, 1.0, 1.4, .3, .08, { top: C.BARK, side: C.BARK, bevel: C.BRASS, bottom: C.BARK, front: C.INK }));
    kit.group({ pos: [0, 15.4, -3.4], rot: [PI / 2, 0, 0] }, () => kit.lathe([[.9, -.6], [.9, 1.0], [.6, 1.3]], { n: 8, capStart: true, capEnd: true, color: C.BARK_DARK }));
  });
  world('WindmillSails', { smooth: 0, tint: 'E9DFC7', kind: 'prop', range: 1200 }, kit => {
    // Four lattice sails around a hub (axis along -Z, centred at the origin).
    kit.group({ rot: [PI / 2, 0, 0] }, () => kit.lathe([[.9, -.4], [.95, .3], [.5, .7], [0, .9]], { n: 8, capStart: true, color: C.BRASS }));
    for (let b = 0; b < 4; b++) kit.group({ rot: [0, 0, b * PI / 2 + .3] }, () => {
      kit.box(0, 6.2, 0, .45, 12, .45, C.BARK);
      for (const s of [-1, 1]) kit.box(s * 1.0, 6.9, -.05, .14, 10, .14, C.BARK);
      for (let k = 0; k < 7; k++) kit.box(0.35, 2.4 + k * 1.45, -.05, 2.2, .12, .1, C.BARK_DARK);
      kit.box(.45, 7.0, .05, 1.8, 9.6, .06, TINT);
    });
  });
  world('Caldera', { smooth: 20, tint: 'FF8A3D', kind: 'tower', range: 1200 }, kit => {
    // Jagged crater wall around a lava pool, with basalt columns and vents.
    kit.lathe([[9, -.3], [8.6, .8], [7.4, 2.6], [6.2, 3.8], [5.4, 3.5], [5.0, 2.0], [4.7, .7]], {
      n: 22, capStart: false, jitter: (l, i) => 1 + (hash(l, i, 481) - .5) * (l === 3 ? .2 : .1), lift: (l, i) => l === 3 ? (hash(i, 3, 482) - .3) * 1.8 : 0,
      color: (l, i) => l <= 1 ? C.STONE_DARK : l === 2 ? (hash(i, l, 483) < .3 ? C.EMBER : C.IRON) : l === 3 ? C.INK : (hash(i, l, 484) < .5 ? C.EMBER : C.IRON),
    });
    kit.lathe([[4.8, .7], [4.2, .75], [2.4, .85], [0, .9]], { n: 22, color: (l, i) => l === 0 ? C.EMBER : hash(i, l, 485) < .35 ? C.FLAME : TINT });
    for (let k = 0; k < 9; k++) {
      const a = k * 2 * PI / 9 + hash(k, 1, 486) * .4, d = 8.4 + hash(k, 2, 486) * 1.2, h = 2 + hash(k, 3, 486) * 4;
      kit.group({ pos: [Math.cos(a) * d, 0, Math.sin(a) * d] }, () => kit.lathe([[.8, -.3], [.75, h], [.55, h + .3]], { n: 6, phase: k, capStart: true, capEnd: true, color: (l, i) => l === 2 ? C.EMBER : C.STONE_DARK }));
    }
    for (let k = 0; k < 3; k++) { const a = k * 2.1 + .5; kit.spindle(Math.cos(a) * 2.6, 1.6, Math.sin(a) * 2.6, .6, 1.6, C.IRON, 6, .4) }
  });
  world('CrystalSpire', { smooth: 0, tint: 'B59CFF', kind: 'tower', range: 1200 }, kit => {
    kit.blob(0, .4, 0, 4.2, 1.6, 4.2, { sub: 1, amount: .18, seed: 491, squash: .4, color: (n, m, i) => n[1] > .6 ? C.STONE_DARK : C.INK });
    const shards = [[0, 0, 0, 0, 22, 1.6], [1.6, .4, .5, -.25, 12, 1.0], [-1.5, -.6, -.3, .3, 14, 1.1], [.4, 1.7, .35, .1, 9, .8], [-.6, -1.8, -.4, -.12, 10, .8], [2.4, -1.4, .2, -.45, 7, .6], [-2.6, 1.2, -.3, .5, 6, .6]];
    shards.forEach(([x, z, rx, rz, len, r], k) => kit.group({ pos: [x, .8, z], rot: [rx, k * .9, rz] }, () =>
      kit.lathe([[r * .8, -.5], [r, len * .1], [r * 1.05, len * .7], [0, len]], { n: 6, phase: k * .3, capStart: true, color: (l, i) => l === 2 ? (i % 2 ? TINT_LIGHT : TINT) : (i % 3 === 0 ? TINT_LIGHT : TINT_DARK) })));
    for (let k = 0; k < 6; k++) { const a = k * PI / 3 + .2; kit.jewel(Math.cos(a) * 4.4, 9 + k * 1.6, Math.sin(a) * 4.4, .4, .9, .4, k % 2 ? C.GLINT : TINT_LIGHT) }
  });
  world('Observatory', { smooth: 35, tint: '39898E', kind: 'tower', range: 1200 }, kit => {
    // Half-sunk drum (base below grade), ribbed dome with a slot, brass telescope.
    kit.lathe([[6.4, -1.5], [6.4, 2.6], [6.7, 2.9], [6.7, 3.2]], { n: 18, capStart: true, color: (l, i) => l === 0 ? (i % 2 ? C.STONE : C.STONE_LIGHT) : C.MARBLE, jitter: (l, i) => l === 0 ? 1 + (hash(l, i, 501) - .5) * .02 : 1 });
    const dome = [];
    for (let k = 0; k < 6; k++) { const a = k / 6 * PI / 2; dome.push([Math.cos(a) * 6.1, 3.2 + Math.sin(a) * 6.1]) }
    dome.push([0, 9.3]);
    kit.lathe(dome, { n: 18, color: (l, i) => (i === 0 || i === 1) ? C.INK : (i % 3 === 0 ? C.BRASS : (l % 2 ? TINT : TINT_DARK)) });
    for (let i = 0; i < 9; i++) { const a = i * 2 * PI / 9; kit.bevelBox(Math.cos(a) * 6.55, 1.2, Math.sin(a) * 6.55, .7, 2.2, .7, .06, C.MARBLE) }
    kit.group({ pos: [0, 7.5, -2.2], rot: [-.75, 0, 0] }, () => {
      kit.lathe([[.9, -1.5], [1.0, 2.5], [1.25, 2.7], [1.25, 3.2]], { n: 10, capStart: true, capEnd: true, color: (l) => l === 2 ? C.GLINT : C.BRASS });
      for (const y of [0, 1.6]) kit.ring(1.02, .14, .2, C.IRON, 10, PI / 2, 0, PI * 2, y);
    });
    kit.bevelBox(0, 1.2, -6.5, 2.2, 2.8, .8, .1, { top: C.MARBLE, side: C.MARBLE, bevel: C.BRASS, bottom: C.STONE, front: C.INK });
  });
  world('CompassTower', { smooth: 25, tint: 'F4CD7C', kind: 'tower', range: 1200 }, kit => {
    // Square clock-and-compass tower with a copper spire: the hub's landmark.
    kit.bevelBox(0, 1, 0, 7, 2, 7, .2, { top: C.STONE_LIGHT, side: C.STONE, bevel: C.STONE_LIGHT, bottom: C.STONE_DARK });
    kit.slab(0, 8, 0, 5.6, 5.6, 4.6, 4.6, 12, C.MARBLE, C.STONE_LIGHT);
    for (const y of [5, 9, 13]) kit.bevelBox(0, y, 0, 5.6 - (y - 5) * .08, .4, 5.6 - (y - 5) * .08, .08, C.STONE);
    kit.bevelBox(0, 15.6, 0, 5.4, 3.2, 5.4, .2, { top: C.STONE, side: C.MARBLE, bevel: C.BRASS, bottom: C.STONE });
    for (let f = 0; f < 4; f++) kit.group({ rot: [0, f * PI / 2, 0] }, () => {
      kit.group({ pos: [0, 15.6, -2.72] }, () => {
        kit.ring(1.15, .28, .12, C.BRASS, 14, 0);
        kit.box(0, .3, -.06, .14, .9, .05, C.INK, .2);
        kit.box(0, .1, -.07, .1, 1.2, .05, C.INK, -1.1);
      });
      kit.bevelBox(0, 7.5, -2.62, 1.1, 2.4, .3, .1, { top: C.STONE, side: C.STONE, bevel: C.BRASS, bottom: C.STONE, front: C.INK });
      kit.bevelBox(0, 1.6, -3.55, 2.4, 3.2, .3, .1, { top: C.BARK, side: C.BARK_DARK, bevel: C.BRASS, bottom: C.BARK, front: C.BARK_DARK });
    });
    kit.lathe([[3.9, 17.2], [3.9, 17.6], [2.6, 20.5], [.9, 24.5], [0, 26.5]], { n: 8, phase: PI / 8, capStart: true, color: (l, i) => l === 0 ? C.BRASS : (i % 2 ? TINT : TINT_DARK) });
    kit.jewel(0, 27.3, 0, .5, 1.0, .5, C.MINT);
  });

  // -------------------------------------------------------------------------
  // Prop kit.
  // -------------------------------------------------------------------------
  world('FenceRun', { smooth: 20, tint: '8A6240', fit: [[-.3, 0, -4], [.3, 1.9, 4]], kind: 'prop' }, kit => {
    for (let i = 0; i < 5; i++) kit.group({ pos: [0, 0, -4 + i * 2] }, () => kit.lathe([[.18, 0], [.17, 1.65], [.12, 1.9], [0, 1.95]], { n: 5, phase: i, capStart: true, color: l => l === 1 ? TINT_DARK : TINT, jitter: wave(510 + i, .06) }));
    for (const y of [.65, 1.35]) kit.tube([[0, y, -4], [.04, y - .05, -2], [-.03, y + .03, 0], [.03, y - .04, 2], [0, y, 4]], .09, { n: 4, color: (i, k) => k % 2 ? TINT : TINT_LIGHT });
    for (const z of [-3.8, .2]) kit.tube([[0, .25, z], [0, 1.5, z + 1.6]], .06, { n: 4, color: TINT_DARK });
  });
  world('BannerPole', { smooth: 25, tint: 'C15557', kind: 'sign' }, kit => {
    kit.lathe([[.5, 0], [.45, .3], [.16, .45], [.15, 3.6], [.19, 3.7], [.15, 3.8], [.14, 7.4], [.2, 7.5], [.12, 7.7], [0, 8.1]], { n: 8, capStart: true, color: l => l <= 1 ? C.STONE : l === 3 || l >= 6 ? C.BRASS : C.BARK });
    for (const x of [.15, 1.85]) { kit.tube([[x, 6.85, 0], [x, 6.4, 0]], .03, { n: 3, color: C.GOLD }); kit.jewel(x, 6.3, 0, .1, .16, .1, C.GOLD) }
    kit.box(.9, 7.0, 0, 2.0, .14, .14, C.BRASS);
    kit.group({ pos: [0, 6.95, 0] }, () => {
      kit.prism([[.05, -.1], [1.75, -.1], [1.75, -3.6], [.9, -3.0], [.05, -3.6]], .1, TINT, TINT_DARK, 0);
      kit.prism([[.6, -1.0], [1.2, -1.0], [1.2, -1.8], [.9, -2.1], [.6, -1.8]], .02, C.GOLD, C.GOLD, -.07);
    });
  });
  world('TwinLantern', { smooth: 30, tint: 'FFE08A', kind: 'lamp' }, kit => {
    kit.lathe([[.55, 0], [.5, .4], [.2, .55], [.16, 4.6], [.24, 4.8], [0, 5.3]], { n: 6, capStart: true, color: l => l <= 1 ? C.STONE : C.IRON });
    for (const s of [-1, 1]) {
      kit.tube([[0, 4.4, 0], [s * .7, 4.7, 0], [s * 1.2, 4.5, 0]], .06, { n: 4, color: C.IRON });
      kit.group({ pos: [s * 1.2, 3.7, 0] }, () => {
        kit.spindle(0, .78, 0, .32, .25, C.IRON, 6, .3);
        kit.jewel(0, .25, 0, .22, .4, .22, TINT);
        for (let k = 0; k < 4; k++) { const a = k * PI / 2 + PI / 4; kit.box(Math.cos(a) * .25, .25, Math.sin(a) * .25, .05, .9, .05, C.IRON) }
        kit.spindle(0, -.25, 0, .3, .14, C.IRON, 6, .8);
      });
    }
  });
  world('CargoStack', { smooth: 0, kind: 'prop' }, kit => {
    const crate = (x, y, z, s, a) => kit.group({ pos: [x, y, z], rot: [0, a, 0] }, () => {
      kit.bevelBox(0, s / 2, 0, s, s, s, .05, C.PLANK);
      for (const f of [-1, 1]) { kit.box(0, s / 2, f * s / 2, s * 1.02, .14, .05, C.BARK); kit.box(f * s / 2, s / 2, 0, .05, .14, s * 1.02, C.BARK) }
    });
    crate(0, 0, 0, 1.5, .1); crate(1.6, 0, .2, 1.3, -.2); crate(.5, 1.5, .1, 1.2, .5);
    for (const [x, z] of [[-1.3, .4], [-1.1, -.8]]) kit.blob(x, .5, z, .55, .55, .5, { sub: 1, seed: 540 + x, amount: .05, squash: .7, color: n => n[1] > .7 ? C.STRAW : C.CLOTH });
    kit.group({ pos: [1.6, 1.3, .2] }, () => kit.lathe([[.4, 0], [.48, .45], [.4, .9]], { n: 8, capStart: true, capEnd: true, color: l => l === 0 ? C.PLANK : C.BARK }));
  });
  world('HayCart', { smooth: 25, kind: 'prop' }, kit => {
    kit.bevelBox(0, 1.1, 0, 2.4, .25, 3.6, .05, C.PLANK);
    for (const s of [-1, 1]) {
      kit.bevelBox(s * 1.15, 1.55, 0, .14, .7, 3.6, .03, C.BARK);
      kit.group({ pos: [s * 1.3, .75, .9], rot: [0, 0, PI / 2] }, () => { kit.ring(.7, .14, .14, C.BARK_DARK, 10, PI / 2); kit.lathe([[.15, -.1], [.15, .1]], { n: 6, capStart: true, capEnd: true, color: C.IRON }) });
      kit.group({ pos: [s * 1.3, .75, -1.0], rot: [0, 0, PI / 2] }, () => kit.ring(.7, .14, .14, C.BARK_DARK, 10, PI / 2));
    }
    kit.blob(0, 2.0, .1, 1.1, .85, 1.6, { sub: 1, seed: 570, amount: .12, squash: .9, color: (n, m, i) => hash(i, 1, 571) < .35 ? C.AMBER : C.STRAW });
    for (const s of [-1, 1]) kit.box(s * .5, .95, -2.5, .12, .12, 1.8, C.BARK);
  });
};
