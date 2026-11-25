// Environment art pass (docs/DEPTH-CONTRACT.md §54): island dressing meshes —
// ground clutter (grass, flowers, pebbles, stones), shrubs (bushes, ferns,
// reeds), tree species per biome (broadleaf, blossom, willow, spire pine,
// mushroom, crystal), cliff dressing (hanging roots, vine curtains, crystal
// veins) and the satellite rocks that float beside every island. Loaded by
// art/generate-props.cjs into their own lazily decoded catalog
// (art/TerrainCatalog.lua, ReplicatedStorage.AetherTerrainArt). terrain.client.lua
// places them through the MeshForge "dress" pool; they are never server parts.
//
// Rules (asserted by the generator and by verify-mesh / verify-environment):
//   * smooth-shaded: meta.smooth >= 40 (corner normals blend across facets);
//   * only round primitives (lathe, tube, blob, loft) with >= 10 segments
//     (`n: 10` or more; blobs subdivide at least once) — no boxes, jewels,
//     prisms, slabs or spindles, so nothing reads as low-poly;
//   * colour by height, band or position (centre), never by facet index;
//   * TINT is the species' region colour (leaves, petals, crystal, stone);
//     TINT_DARK / TINT_LIGHT are derived from it, so a tint variant recolours
//     the whole plant consistently.
// Units are studs at scale 1, +Y up, origin on the ground at the base centre
// (cliff dressing: origin at the rim attachment, hanging toward -Y, wall
// facing -Z; satellites: origin at the grass top centre).
'use strict';
module.exports = ({ terrain, C, PI, hash }) => {
  const { TINT, TINT_DARK, TINT_LIGHT } = C;
  const N = 10; // minimum ring segments (facet rule)
  const rnd = (a, b, s) => hash(a, b, s);
  // Foliage shading by the face normal (lit crown, shaded underside) plus a
  // positional patch noise (centre), never the facet index.
  const leafShade = seed => (n, m) => n[1] > .55 ? (rnd(Math.floor(m[0] * .6 + 40), Math.floor(m[2] * .6 + 40), seed) < .55 ? TINT_LIGHT : TINT)
    : n[1] < -.3 ? TINT_DARK : TINT;
  // Stones: moss cap, body, shaded foot by height bands of the blob itself.
  const stoneShade = (seed, moss = true, ry = 1) => (n, m) => m[1] > ry * .62 ? (moss ? C.MOSS : TINT_LIGHT) : m[1] < -ry * .25 ? TINT_DARK : TINT;
  // A curved blade: a thin flattened lathe whose tip leans out (wobble).
  const blade = (kit, x, z, h, w, lean, yaw, colours, seed) => kit.group({ pos: [x, 0, z], rot: [0, yaw, 0] }, () =>
    kit.lathe([[w, -.05], [w * .82, h * .4], [w * .45, h * .78], [0, h]], {
      n: N, sz: .42, phase: rnd(seed, 1, 3) * .3,
      wobble: level => [lean * h * (level / 3) ** 2, 0],
      color: (level, i, c) => c[1] < h * .32 ? colours[0] : (rnd(seed, 7, 1) < .35 ? colours[2] : colours[1]),
    }));
  const tuft = (kit, count, spread, hMin, hMax, seed, colours) => {
    for (let k = 0; k < count; k++) {
      const a = k * 2.399 + rnd(k, 1, seed) * .5, d = spread * Math.sqrt((k + .5) / count);
      const h = hMin + (hMax - hMin) * rnd(k, 2, seed);
      blade(kit, Math.cos(a) * d, Math.sin(a) * d, h, .07 + rnd(k, 3, seed) * .05, .25 + rnd(k, 4, seed) * .35, -a + (rnd(k, 5, seed) - .5) * .8, colours, seed + k);
    }
  };
  const GRASS = [TINT_DARK, TINT, TINT_LIGHT];
  // Bark trunk: a jittered lathe with a flared root foot (no flat caps).
  const trunk = (kit, profile, seed, { wobble, dark = C.BARK_DARK, light = C.BARK } = {}) =>
    kit.lathe(profile, {
      n: 12, phase: rnd(seed, 1, 1), jitter: (level, i) => 1 + (rnd(level, i, seed) - .5) * .12, wobble,
      color: (level, i, c) => c[1] < .6 ? dark : (Math.floor(c[1] * 1.4 + Math.atan2(c[2], c[0]) * 1.6 + 20) % 4 === 0 ? dark : light),
    });
  const ROOT_FOOT = (r, top, extra = []) => [[0, -.35], [r * 1.45, -.3], [r * 1.25, .12], [r * 1.02, .55], ...extra, [r * .4, top - .25], [0, top]];
  const branch = (kit, pts, r0, seed, color = C.BARK) => kit.tube(pts, pts.map((_, i) => r0 * (1 - i / pts.length * .75)), { n: N, color, capStart: false, capEnd: true });
  const crownBlob = (kit, x, y, z, rx, ry, rz, seed, sub = 1, squash = .55) =>
    kit.blob(x, y, z, rx, ry, rz, { sub, seed, amount: .1, squash, color: leafShade(seed) });

  // -------------------------------------------------------------------------
  // Ground clutter (kind 'clutter'): instanced in the hundreds, so each stays
  // a few hundred triangles; sway mode 'grass' / 'bush'.
  // -------------------------------------------------------------------------
  terrain('GrassTuft', { smooth: 60, tint: '6FA956', kind: 'clutter' }, kit => tuft(kit, 11, .55, .55, 1.15, 901, GRASS));
  terrain('MeadowGrass', { smooth: 60, tint: '7DB35C', kind: 'clutter' }, kit => {
    tuft(kit, 10, 1.0, .9, 1.9, 911, GRASS);
    // Seed heads on the tallest stalks.
    for (let k = 0; k < 2; k++) {
      const a = k * 2.1 + .4, d = .45;
      kit.group({ pos: [Math.cos(a) * d, 0, Math.sin(a) * d], rot: [(rnd(k, 1, 912) - .5) * .4, 0, (rnd(k, 2, 912) - .5) * .4] }, () => {
        kit.lathe([[.035, 0], [.03, 1.6], [0, 1.75]], { n: N, color: () => TINT });
        kit.blob(0, 1.95, 0, .08, .26, .08, { sub: 1, seed: 913 + k, color: () => C.STRAW });
      });
    }
  });
  terrain('FlowerSprigs', { smooth: 55, tint: 'E58AB0', kind: 'clutter' }, kit => {
    tuft(kit, 4, .55, .4, .8, 921, [C.LEAF_DARK, C.LEAF, C.LEAF]);
    for (let k = 0; k < 5; k++) {
      const a = k * 2.399 + .3, d = .2 + .45 * rnd(k, 1, 922), h = .7 + rnd(k, 2, 922) * .55;
      const x = Math.cos(a) * d, z = Math.sin(a) * d, lean = (rnd(k, 3, 922) - .5) * .25;
      kit.group({ pos: [x, 0, z] }, () => kit.lathe([[.03, -.05], [.028, h * .5], [.02, h]], { n: N, wobble: level => [lean * level, 0], color: () => C.LEAF_DARK }));
      kit.group({ pos: [x + lean * 2, h, z], rot: [(rnd(k, 4, 922) - .5) * .5, a, (rnd(k, 5, 922) - .5) * .5] }, () => {
        // Petal cup: a scalloped flattened lathe (TINT), golden centre.
        kit.lathe([[.04, -.05], [.2, .02], [.24, .09], [.1, .12], [0, .1]], {
          n: N, jitter: (level, i) => level >= 1 && level <= 2 ? (i % 2 ? 1.18 : .78) : 1,
          color: (level, i, c) => c[1] > .085 && Math.hypot(c[0], c[2]) < .12 ? C.GOLD : TINT,
        });
      });
    }
  });
  terrain('Pebbles', { smooth: 55, tint: '8C8F92', kind: 'clutter' }, kit => {
    for (let k = 0; k < 6; k++) {
      const a = k * 2.399, d = .25 + .7 * rnd(k, 1, 931), s = .14 + rnd(k, 2, 931) * .2;
      kit.blob(Math.cos(a) * d, s * .3, Math.sin(a) * d, s * 1.3, s * .7, s, { sub: 1, seed: 932 + k, amount: .12, squash: .5, color: stoneShade(933 + k, false, s * .7) });
    }
  });
  terrain('MossStone', { smooth: 50, tint: '858A8F', kind: 'clutter' }, kit => {
    kit.blob(0, .35, 0, 1.0, .65, .8, { sub: 2, seed: 941, amount: .14, squash: .35, color: stoneShade(941, true, .65) });
    kit.blob(.95, .14, .45, .35, .24, .3, { sub: 1, seed: 942, amount: .1, squash: .4, color: stoneShade(942, true, .24) });
    tuft(kit, 4, .35, .3, .6, 943, [C.LEAF_DARK, C.MOSS, C.LEAF]);
  });
  terrain('StoneOutcrop', { smooth: 45, tint: '7E8388', kind: 'clutter' }, kit => {
    kit.blob(0, .9, 0, 1.7, 1.4, 1.3, { sub: 2, seed: 951, amount: .18, squash: .3, color: stoneShade(951, true, 1.4) });
    kit.blob(1.6, .5, .7, .9, .8, .8, { sub: 1, seed: 952, amount: .16, squash: .3, color: stoneShade(952, true, .8) });
    kit.blob(-1.3, .35, .9, .7, .55, .6, { sub: 1, seed: 953, amount: .16, squash: .3, color: stoneShade(953, true, .55) });
    kit.blob(-.4, .25, -1.3, .55, .45, .5, { sub: 1, seed: 954, amount: .15, squash: .3, color: stoneShade(954, true, .45) });
  });
  terrain('MushroomCluster', { smooth: 55, tint: 'B07AD6', kind: 'clutter' }, kit => {
    for (let k = 0; k < 5; k++) {
      const a = k * 2.399 + .5, d = k === 0 ? 0 : .35 + .35 * rnd(k, 1, 961), h = k === 0 ? .9 : .35 + rnd(k, 2, 961) * .45, r = h * .45;
      kit.group({ pos: [Math.cos(a) * d, 0, Math.sin(a) * d], rot: [(rnd(k, 3, 961) - .5) * .35, 0, (rnd(k, 4, 961) - .5) * .35] }, () => {
        kit.lathe([[r * .32, -.05], [r * .26, h * .6], [r * .22, h]], { n: N, color: () => C.CLOTH });
        kit.lathe([[r * .2, h - .02], [r * .95, h + r * .05], [r, h + r * .25], [r * .7, h + r * .55], [0, h + r * .7]], {
          n: N, color: (level, i, c) => level === 0 ? TINT_DARK : c[1] > h + r * .5 ? TINT_LIGHT : TINT,
        });
      });
    }
  });
  terrain('ShardCluster', { smooth: 50, tint: '8FE3FF', kind: 'clutter' }, kit => {
    kit.blob(0, .15, 0, .8, .4, .7, { sub: 1, seed: 971, amount: .12, squash: .3, color: (n) => n[1] > .6 ? C.STONE_LIGHT : C.STONE_DARK });
    for (let k = 0; k < 5; k++) {
      const a = k * 2.399, len = 1.0 + rnd(k, 1, 972) * 1.1, r = .12 + rnd(k, 2, 972) * .1;
      kit.group({ pos: [Math.cos(a) * .3, .2, Math.sin(a) * .3], rot: [Math.sin(a) * .5, 0, -Math.cos(a) * .5] }, () =>
        kit.lathe([[r * .8, -.15], [r, len * .55], [r * .55, len * .85], [0, len]], {
          n: N, color: (level, i, c) => c[1] > len * .6 ? TINT_LIGHT : TINT,
        }));
    }
  });

  // -------------------------------------------------------------------------
  // Shrubs (kind 'shrub'): bushes, ferns and waterside reeds.
  // -------------------------------------------------------------------------
  terrain('LeafyBush', { smooth: 55, tint: '5E9A4E', kind: 'shrub' }, kit => {
    crownBlob(kit, 0, .9, 0, 1.25, .95, 1.15, 1001, 2, .5);
    for (let k = 0; k < 4; k++) {
      const a = k * PI / 2 + .4;
      crownBlob(kit, Math.cos(a) * .95, .65 + rnd(k, 1, 1002) * .3, Math.sin(a) * .9, .75, .62, .7, 1003 + k, 1, .5);
    }
  });
  terrain('Fern', { smooth: 55, tint: '4F8F45', kind: 'shrub' }, kit => {
    for (let k = 0; k < 9; k++) {
      const a = k * 2 * PI / 9 + rnd(k, 1, 1011) * .3, tilt = .8 + rnd(k, 2, 1011) * .25, len = 1.4 + rnd(k, 3, 1011) * .5;
      kit.group({ rot: [0, -a + PI / 2, 0] }, () => kit.group({ rot: [tilt, 0, 0] }, () =>
        kit.lathe([[.05, -.05], [.36, len * .25], [.42, len * .55], [.24, len * .82], [0, len]], {
          n: N, sz: .16, wobble: level => [0, -.045 * level * level],
          color: (level, i, c) => c[1] < len * .2 ? TINT_DARK : c[1] > len * .7 ? TINT_LIGHT : TINT,
        })));
    }
    crownBlob(kit, 0, .12, 0, .35, .2, .35, 1012, 1, .5);
  });
  terrain('ReedClump', { smooth: 55, tint: '7C9A4E', kind: 'shrub' }, kit => {
    tuft(kit, 12, .7, 1.6, 2.8, 1021, GRASS);
    for (let k = 0; k < 3; k++) {
      const a = k * 2.2 + .9, d = .35, h = 2.4 + rnd(k, 1, 1022) * .6;
      kit.group({ pos: [Math.cos(a) * d, 0, Math.sin(a) * d], rot: [(rnd(k, 2, 1022) - .5) * .2, 0, (rnd(k, 3, 1022) - .5) * .2] }, () => {
        kit.lathe([[.04, -.05], [.035, h], [0, h + .5]], { n: N, color: () => TINT_DARK });
        kit.blob(0, h - .15, 0, .1, .32, .1, { sub: 1, seed: 1023 + k, color: () => C.BARK });
      });
    }
  });

  // -------------------------------------------------------------------------
  // Tree species (kind 'foliage'): 6 silhouettes; terrain.client.lua picks 3+
  // per biome and tints them with the region palette.
  // -------------------------------------------------------------------------
  // Broadleaf: a round, lobed oak-like crown on a stout flared trunk.
  terrain('BroadleafTree', { smooth: 55, tint: '5E9C4C', kind: 'foliage' }, kit => {
    trunk(kit, ROOT_FOOT(.7, 7.4, [[.66, 2.5], [.6, 4.8], [.52, 6.4]]), 1101);
    branch(kit, [[0, 5.2, 0], [1.5, 6.6, .4], [2.6, 7.8, .6]], .3, 1102);
    branch(kit, [[0, 5.6, 0], [-1.4, 6.9, -.5], [-2.4, 8.0, -.9]], .28, 1103);
    branch(kit, [[0, 6.0, 0], [-.3, 7.4, 1.4], [-.4, 8.4, 2.2]], .26, 1104);
    crownBlob(kit, 0, 9.4, 0, 3.9, 2.9, 3.7, 1105, 2);
    for (const [x, y, z, r, s] of [[2.8, 8.6, .6, 2.3, 1106], [-2.6, 8.8, -1.0, 2.4, 1107], [-.4, 8.9, 2.6, 2.2, 1108], [.9, 9.0, -2.5, 2.2, 1109], [.2, 11.0, .2, 2.4, 1110]])
      crownBlob(kit, x, y, z, r, r * .8, r, s);
  });
  // Blossom: a low, wide umbrella of pink bloom on a leaning, twisting trunk.
  terrain('BlossomTree', { smooth: 55, tint: 'F2A7C3', kind: 'foliage' }, kit => {
    trunk(kit, ROOT_FOOT(.5, 5.6, [[.46, 2], [.42, 3.8], [.36, 5]]), 1201, { wobble: level => [Math.sin(level * .9) * .35 + level * .12, Math.cos(level * .7) * .2] });
    branch(kit, [[.6, 4.6, 0], [2.2, 5.6, .5], [3.6, 6.2, .9]], .22, 1202);
    branch(kit, [[.5, 4.8, 0], [-1.3, 5.9, -.8], [-2.8, 6.4, -1.4]], .2, 1203);
    branch(kit, [[.6, 5.0, 0], [.4, 6.1, 1.8], [.1, 6.6, 3.0]], .2, 1204);
    crownBlob(kit, .7, 7.0, 0, 3.4, 1.7, 3.2, 1205, 2, .35);
    for (const [x, y, z, r, s] of [[3.5, 6.7, .9, 1.9, 1206], [-2.8, 6.9, -1.4, 2.0, 1207], [.1, 6.9, 3.0, 1.8, 1208], [1.2, 6.8, -2.6, 1.7, 1209], [.8, 8.1, .2, 1.8, 1210]])
      crownBlob(kit, x, y, z, r, r * .6, r, s, 1, .35);
  });
  // Willow: a domed crown spilling into a long draped curtain of fronds.
  terrain('WillowTree', { smooth: 50, tint: '7FAE5A', kind: 'foliage' }, kit => {
    trunk(kit, ROOT_FOOT(.75, 8.4, [[.7, 2.4], [.6, 5], [.5, 7.2]]), 1301, { wobble: level => [level * .06, 0] });
    branch(kit, [[0, 6.8, 0], [1.6, 8.4, .3], [3.0, 8.8, .4]], .26, 1302);
    branch(kit, [[0, 7.0, 0], [-1.5, 8.5, -.6], [-2.8, 8.9, -.9]], .26, 1303);
    crownBlob(kit, 0, 9.6, 0, 3.4, 2.0, 3.4, 1304, 2, .6);
    // The curtain: an open lathe hanging from the crown's rim; strands end at
    // ragged heights (lift on the bottom ring) and sway gently with the wind.
    kit.lathe([[1.6, 10.9], [3.4, 10.3], [4.6, 9.0], [5.1, 7.0], [5.0, 4.8], [4.8, 2.6]], {
      n: 24, phase: .1,
      jitter: (level, i) => level >= 2 ? 1 + (rnd(level, i, 1305) - .5) * .14 : 1,
      lift: (level, i) => level === 5 ? rnd(i, 5, 1306) * 1.9 : level === 4 ? rnd(i, 4, 1306) * .7 : 0,
      color: (level, i, c) => c[1] > 9.5 ? TINT_LIGHT : c[1] < 4.2 ? TINT_DARK : TINT,
    });
  });
  // Spire pine: tall and narrow, drooping needle tiers (Windpine, Skyreach).
  terrain('SpirePine', { smooth: 50, tint: '3F7550', kind: 'foliage' }, kit => {
    trunk(kit, ROOT_FOOT(.45, 15.5, [[.42, 3], [.32, 8], [.2, 13]]), 1401);
    const tiers = [[3.1, 3.0], [2.8, 4.9], [2.45, 6.8], [2.05, 8.6], [1.65, 10.3], [1.25, 11.9], [.85, 13.3], [.5, 14.6]];
    tiers.forEach(([r, y], t) => kit.lathe([[r * .2, y + .5], [r, y - .35], [r * .92, y - .55], [r * .55, y + .25], [r * .28, y + 1.25], [0, y + 1.85]], {
      n: 12, phase: t * .7,
      jitter: (level, i) => level === 1 || level === 2 ? 1 + (rnd(i, t, 1402) - .5) * .18 : 1,
      lift: (level, i) => level === 1 || level === 2 ? (rnd(i, t, 1403) - .5) * .3 : 0,
      color: (level, i, c) => level <= 2 ? TINT_DARK : c[1] > y + .9 ? TINT_LIGHT : TINT,
    }));
  });
  // Mushroom tree: a giant toadstool with gills and glowing spots (Gloomhollow).
  terrain('MushroomTree', { smooth: 55, tint: '9C5FD0', kind: 'foliage' }, kit => {
    kit.lathe([[0, -.35], [1.5, -.3], [1.25, .2], [.95, .8], [.85, 3], [.8, 5.2], [.95, 6.4], [.5, 6.6], [0, 6.62]], {
      n: 14, wobble: level => [Math.sin(level * .5) * .25, 0], jitter: (level, i) => 1 + (rnd(level, i, 1501) - .5) * .08,
      color: (level, i, c) => c[1] < .5 ? C.STONE_DARK : C.CLOTH,
    });
    // Cap: wide dome with a shaded gill skirt underneath.
    kit.lathe([[.9, 6.3], [3.2, 6.1], [4.4, 6.2], [4.7, 6.6], [4.3, 7.6], [3.2, 8.5], [1.6, 9.1], [0, 9.25]], {
      n: 20, jitter: (level, i) => level >= 2 && level <= 4 ? 1 + (rnd(level, i, 1502) - .5) * .1 : 1,
      color: (level, i, c) => level <= 1 ? TINT_DARK : (c[1] > 8.4 ? TINT_LIGHT : TINT),
    });
    for (let k = 0; k < 7; k++) {
      const a = k * 2.399, d = 1.2 + rnd(k, 1, 1503) * 2.2, y = 9.1 - d * d * .11;
      kit.blob(Math.cos(a) * d, y, Math.sin(a) * d, .32, .14, .32, { sub: 1, seed: 1504 + k, color: () => C.GLINT });
    }
    // Two small toadstools at the foot.
    for (const [x, z, h] of [[1.9, .9, 1.3], [-1.6, -1.4, 1.0]]) kit.group({ pos: [x, 0, z] }, () => {
      kit.lathe([[.18, -.05], [.15, h * .7], [.14, h]], { n: N, color: () => C.CLOTH });
      kit.lathe([[.15, h - .05], [.55, h], [.6, h + .14], [.35, h + .35], [0, h + .42]], { n: N, color: (level) => level === 0 ? TINT_DARK : TINT });
    });
  });
  // Crystal tree: a stone trunk branching into clusters of glowing crystal.
  terrain('CrystalTree', { smooth: 50, tint: '9DE6FF', kind: 'foliage' }, kit => {
    trunk(kit, ROOT_FOOT(.6, 6.4, [[.55, 2.2], [.48, 4.2], [.4, 5.6]]), 1601, { dark: C.STONE_DARK, light: C.STONE });
    const tips = [[2.6, 7.4, .4], [-2.3, 7.8, -.9], [-.2, 8.3, 2.4], [.7, 8.9, -2.2], [.1, 9.6, .1]];
    tips.forEach(([x, y, z], k) => {
      branch(kit, [[0, 4.8 + k * .25, 0], [x * .55, y - 1.4, z * .55], [x, y - .4, z]], .24, 1602 + k, C.STONE);
      for (let j = 0; j < 3; j++) {
        const len = 1.7 + rnd(j, k, 1610) * 1.3, r = .26 + rnd(j, k, 1611) * .12;
        const rx = (rnd(j, k, 1612) - .5) * 1.1, rz = (rnd(j, k, 1613) - .5) * 1.1;
        kit.group({ pos: [x, y - .5, z], rot: [rx, j * 2.1, rz] }, () =>
          kit.lathe([[r * .7, -.2], [r, len * .5], [r * .65, len * .82], [0, len]], {
            n: N, phase: j, color: (level, i, c) => c[1] > len * .55 ? TINT_LIGHT : TINT,
          }));
      }
    });
  });

  // -------------------------------------------------------------------------
  // Cliff dressing (kind 'cliff'): hung on the cliff face below the rim.
  // Origin = the attachment point at the rim; the wall lies at z = 0 and the
  // pieces hang down (-Y) and out (-Z), so one yaw turns them to face out.
  // -------------------------------------------------------------------------
  terrain('HangingRoots', { smooth: 55, tint: '6A4A32', kind: 'cliff' }, kit => {
    for (let k = 0; k < 5; k++) {
      const x = (k - 2) * .55 + (rnd(k, 1, 1701) - .5) * .3, len = 2.6 + rnd(k, 2, 1701) * 3.2, out = .35 + rnd(k, 3, 1701) * .4;
      kit.tube([[x, .1, .1], [x * 1.05, -len * .3, -out], [x * 1.1 + .15, -len * .65, -out * .8], [x * 1.12, -len, -out * .7]], [.2, .15, .1, .05],
        { n: N, color: (level, i, c) => c[1] > -.6 ? C.SOIL : TINT, capStart: true, capEnd: true });
    }
    kit.blob(0, -.15, -.2, 1.5, .45, .45, { sub: 1, seed: 1702, amount: .1, color: (n) => n[1] > .3 ? C.MOSS : C.SOIL });
  });
  terrain('VineCurtain', { smooth: 55, tint: '4E8A44', kind: 'cliff' }, kit => {
    for (let k = 0; k < 6; k++) {
      const x = (k - 2.5) * .55, len = 3 + rnd(k, 1, 1801) * 3;
      kit.tube([[x, .1, .05], [x + .1, -len * .35, -.35], [x - .12, -len * .7, -.3], [x, -len, -.25]], [.07, .06, .05, .03], { n: N, color: () => TINT_DARK });
      for (let j = 0; j < 2; j++) {
        const t = .3 + j * .4, y = -len * t;
        kit.blob(x + (j ? .1 : -.1), y, -.4, .3, .26, .2, { sub: 1, seed: 1802 + k * 3 + j, color: leafShade(1803 + k) });
      }
    }
    kit.blob(0, 0, -.25, 1.8, .45, .5, { sub: 1, seed: 1810, amount: .08, color: leafShade(1811) });
  });
  terrain('CrystalVein', { smooth: 50, tint: 'A58BFF', kind: 'cliff' }, kit => {
    // A seam of crystal pushing out of the rock face (origin on the wall).
    kit.blob(0, -1.4, .05, 1.9, 1.3, .35, { sub: 1, seed: 1901, amount: .14, color: (n) => n[2] < -.5 ? TINT_DARK : C.STONE_DARK });
    for (let k = 0; k < 6; k++) {
      const x = (k - 2.5) * .6 + (rnd(k, 1, 1902) - .5) * .3, y = -.6 - rnd(k, 2, 1902) * 1.6, len = .8 + rnd(k, 3, 1902) * 1.1, r = .14 + rnd(k, 4, 1902) * .1;
      kit.group({ pos: [x, y, -.15], rot: [-PI / 2 + (rnd(k, 5, 1902) - .5) * .6, 0, (rnd(k, 6, 1902) - .5) * .6] }, () =>
        kit.lathe([[r * .7, -.1], [r, len * .5], [r * .6, len * .85], [0, len]], { n: N, color: (level, i, c) => c[1] > len * .55 ? TINT_LIGHT : TINT }));
    }
  });

  // -------------------------------------------------------------------------
  // Satellite rocks (kind 'satellite'): small floating islets beside every
  // island; a grassy (or bare) top on a strata keel that tapers to a spire.
  // -------------------------------------------------------------------------
  const satellite = (kit, seed, r, depth, grassy) => {
    const band = c => Math.floor(-c[1] * .9) % 3;
    kit.lathe([[r * .97, .05], [r * 1.02, -.25], [r * .95, -.7], [r * .9, -depth * .22], [r * .72, -depth * .38], [r * .62, -depth * .5],
      [r * .4, -depth * .66], [r * .26, -depth * .8], [r * .1, -depth * .93], [0, -depth]], {
      n: 18, phase: rnd(seed, 1, 1), jitter: (level, i) => level <= 1 ? 1 + (rnd(level, i, seed) - .5) * .06 : 1 + (rnd(level, i, seed) - .5) * .3,
      wobble: level => level > 5 ? [(level - 5) * .12 * r * .15, (level - 5) * .08 * r * .15] : [0, 0],
      color: (level, i, c) => level === 0 ? (grassy ? C.SOIL : TINT_LIGHT) : (band(c) === 0 ? TINT_LIGHT : band(c) === 1 ? TINT : TINT_DARK),
    });
    // Rounded top: grass cap (or a rubble crown) closing the rim.
    kit.lathe([[r * 1.02, -.25], [r * 1.0, .1], [r * .8, .3], [r * .45, .38], [0, .4]], {
      n: 18, jitter: (level, i) => 1 + (rnd(level, i, seed + 7) - .5) * .05,
      color: (level, i, c) => grassy ? (Math.hypot(c[0], c[2]) > r * .9 ? C.LEAF_DARK : C.LEAF) : (level <= 1 ? TINT_LIGHT : TINT),
    });
  };
  terrain('SatelliteRock', { smooth: 45, tint: '6B7380', kind: 'satellite', range: 1200 }, kit => {
    satellite(kit, 2001, 4, 7.5, true);
    kit.blob(1.4, .65, .6, 1.1, .7, .9, { sub: 1, seed: 2002, amount: .12, squash: .4, color: leafShade(2003) });
    kit.blob(-1.5, .5, -.9, .7, .45, .6, { sub: 1, seed: 2004, amount: .12, squash: .4, color: stoneShade(2005, true, .45) });
    for (let k = 0; k < 3; k++) {
      const a = k * 2.1 + .5, x = Math.cos(a) * 3.2, z = Math.sin(a) * 3.2, len = 1.6 + rnd(k, 1, 2006) * 1.4;
      kit.tube([[x, -1.2, z], [x * 1.08, -1.2 - len * .5, z * 1.08], [x * 1.05, -1.2 - len, z * 1.05]], [.12, .08, .03], { n: N, color: () => C.BARK });
    }
  });
  terrain('SatelliteRockBare', { smooth: 45, tint: '5E6470', kind: 'satellite', range: 1200 }, kit => {
    satellite(kit, 2101, 3.2, 6.5, false);
    kit.blob(.8, .55, -.5, .9, .7, .8, { sub: 1, seed: 2102, amount: .16, squash: .4, color: stoneShade(2103, false, .7) });
    kit.blob(-1.0, .4, .7, .6, .5, .55, { sub: 1, seed: 2104, amount: .16, squash: .4, color: stoneShade(2105, false, .5) });
  });
};
