// Wave-4 original world meshes for the client mesh forge (forge.client.lua).
// Loaded by art/generate-props.cjs; every shape is authored here from primitives
// (no imported or copied assets). Units are studs at scale 1, +Y up, fronts face -Z.
//
// world(name, meta, build) meta:
//   smooth: crease angle in degrees for the forge's normal smoothing (0 = flat facets)
//   tint:   default colour (hex) for the TINT slot when a part has no Tint attribute;
//           TINT_DARK / TINT_LIGHT faces are derived from the same colour
//   fit:    [[minX,minY,minZ],[maxX,maxY,maxZ]] authored box that maps onto the tagged
//           part's size (default: the whole mesh). Signs fit the text board, so the
//           frame and crest wrap around the original part, which keeps its SurfaceGui.
//   kind:   grouping used by the preview sheet and tests
'use strict';
module.exports = ({ world, C, PI, hash, jitterOf }) => {
  const { TINT, TINT_DARK, TINT_LIGHT } = C;
  const pick = (seed, i, options) => options[Math.floor(hash(i, seed, 3) * options.length)];
  // Canopy shading: lit crowns, darker undersides and a little painted variation.
  const foliage = seed => (n, m, i) => n[1] > .5 ? (hash(i, seed, 1) < .45 ? TINT_LIGHT : TINT)
    : n[1] < -.35 ? TINT_DARK : (hash(i, seed, 2) < .3 ? TINT_DARK : TINT);
  const rock = (seed, mossy = true) => (n, m, i) => n[1] > .72 && mossy ? (hash(i, seed, 4) < .55 ? C.MOSS : C.STONE_LIGHT)
    : n[1] < -.25 ? C.STONE_DARK : pick(seed, i, [C.STONE, C.STONE, C.STONE_LIGHT, C.STONE_DARK]);
  const barkBands = (seed, base = C.BARK, alt = C.BARK_DARK) => (level, i) => hash(level, i, seed) < .28 ? alt : base;
  // Roots flaring from a trunk base into the ground.
  const roots = (kit, count, radius, height, seed, color = C.BARK, size = .32) => {
    for (let i = 0; i < count; i++) {
      const a = i * 2 * PI / count + hash(i, seed, 9) * .6, out = radius * (1.5 + hash(i, seed, 8) * .7);
      kit.tube([[Math.cos(a) * radius * .4, height, Math.sin(a) * radius * .4], [Math.cos(a) * radius * .95, height * .45, Math.sin(a) * radius * .95], [Math.cos(a) * out, -.05, Math.sin(a) * out]],
        [size, size * .75, size * .28], { n: 5, color });
    }
  };
  // Faceted crystal: hexagonal shaft with a pointed tip and alternating facets.
  const crystal = (kit, x, y, z, rx, rz, len, r, seed) => kit.group({ pos: [x, y, z], rot: [rx, hash(1, seed, 2) * PI, rz] }, () =>
    kit.lathe([[r * .85, -.25], [r, len * .08], [r * 1.06, len * .66], [0, len]], {
      n: 6, capStart: true, phase: hash(seed, 2, 1),
      color: (level, i) => level === 0 ? TINT_DARK : level === 2 ? (i % 2 ? TINT_LIGHT : TINT) : (i % 3 === 0 ? TINT_LIGHT : TINT),
    }));
  const rockBed = (kit, rx, ry, rz, seed, sub = 1) => kit.blob(0, ry * .35, 0, rx, ry, rz, { sub, amount: .16, seed, squash: .25, color: (n, m, i) => n[1] > .8 && hash(i, seed, 5) < .3 ? C.MOSS : rock(seed, false)(n, m, i) });

  // -------------------------------------------------------------------------
  // Trees. Foliage uses the tint slots so the World team can recolour species.
  // -------------------------------------------------------------------------
  world('WindpineTree', { smooth: 50, tint: '4F8A57', kind: 'tree' }, kit => {
    kit.lathe([[.62, 0], [.48, 1.2], [.38, 4.5], [.24, 9], [.08, 13.4]], { n: 7, capStart: true, color: barkBands(3), jitter: jitterOf(4, .06) });
    roots(kit, 5, .6, .9, 11);
    const tiers = [[2.9, 3.0], [2.55, 4.9], [2.15, 6.8], [1.7, 8.6], [1.2, 10.3], [.7, 11.8]];
    tiers.forEach(([r, y], t) => kit.lathe([[r * .18, y + .35], [r, y - .25], [r * .62, y + .55], [r * .3, y + 1.45], [0, y + 2.05]], {
      n: 10, phase: t * .7, capStart: true, capColor: TINT_DARK,
      jitter: (level, i) => level === 1 ? (i % 2 ? 1.12 : .8) * (1 + (hash(i, t, 5) - .5) * .12) : 1,
      lift: (level, i) => level === 1 ? (i % 2 ? -.28 : .12) : 0,
      color: (level, i) => level === 0 ? TINT_DARK : level === 1 ? (i % 2 ? TINT : TINT_DARK) : level === 2 ? (hash(i, t, 6) < .5 ? TINT_LIGHT : TINT) : TINT_LIGHT,
    }));
  });
  world('EmberoakTree', { smooth: 55, tint: 'C9572F', kind: 'tree' }, kit => {
    kit.tube([[0, -.1, 0], [0, 1.8, 0], [.15, 3.6, .1], [.1, 4.6, 0]], [1.05, .78, .72, .6], { n: 8, color: barkBands(7), capStart: true, jitter: jitterOf(7, .08) });
    roots(kit, 6, 1.0, 1.1, 21, C.BARK, .42);
    const limbs = [[[0, 4.2, 0], [1.6, 5.4, .3], [2.9, 6.6, .5]], [[0, 4.3, 0], [-1.5, 5.6, -.4], [-2.8, 6.4, -.8]], [[0, 4.4, 0], [-.3, 6.0, 1.4], [-.4, 7.2, 2.4]], [[0, 4.5, 0], [.4, 6.4, -1.2], [.8, 7.8, -1.6]]];
    for (const limb of limbs) kit.tube(limb, [.42, .3, .16], { n: 5, color: C.BARK });
    const crowns = [[2.9, 7.2, .5, 2.3], [-2.8, 7.0, -.8, 2.4], [-.4, 7.9, 2.3, 2.2], [.8, 8.6, -1.6, 2.3], [0, 9.0, .1, 2.6], [1.5, 8.0, 1.6, 1.8]];
    crowns.forEach(([x, y, z, r], i) => kit.blob(x, y, z, r * 1.08, r * .82, r, { sub: 1, amount: .14, seed: 30 + i, squash: .7, color: foliage(30 + i) }));
  });
  world('GlimmerbarkTree', { smooth: 45, tint: '7FD3C4', kind: 'tree' }, kit => {
    const trunk = [];
    for (let i = 0; i <= 8; i++) { const y = i * 1.35, a = i * .55; trunk.push([Math.cos(a) * .35 * Math.sin(i / 8 * PI), y, Math.sin(a) * .35 * Math.sin(i / 8 * PI)]) }
    kit.tube(trunk, i => .48 - i * .045, { n: 6, color: (i, k) => (i % 3 === 1 ? C.BARK_DARK : C.MARBLE), capStart: true });
    roots(kit, 4, .45, .7, 41, C.MARBLE, .24);
    const branches = [[1, 5.2, 0], [-1, 6.6, .6], [.3, 8.0, -1], [-.5, 9.4, -.2], [.8, 9.0, 1]];
    branches.forEach(([dx, y, dz], b) => {
      const end = [dx * 2.6, y + 1.4, dz * 2.6 + (b % 2 ? .6 : -.6)], mid = [dx * 1.3, y + 1.1, dz * 1.3];
      kit.tube([[0, y - .3, 0], mid, end], [.16, .11, .05], { n: 4, color: C.MARBLE });
      for (let k = 0; k < 6; k++) {
        const t = .35 + k * .13, px = mid[0] + (end[0] - mid[0]) * t + (hash(k, b, 1) - .5) * .9, pz = mid[2] + (end[2] - mid[2]) * t + (hash(k, b, 2) - .5) * .9;
        const py = mid[1] + (end[1] - mid[1]) * t - .45 - hash(k, b, 3) * .4;
        kit.jewel(px, py, pz, .2, .48, .2, k % 3 === 0 ? TINT_LIGHT : TINT);
      }
      kit.blob(end[0], end[1] + .25, end[2], 1.1, .8, 1.1, { sub: 1, amount: .2, seed: 50 + b, squash: .6, color: foliage(50 + b) });
    });
    kit.blob(0, 11.6, 0, 1.5, 1.1, 1.5, { sub: 1, amount: .18, seed: 59, color: foliage(59) });
    kit.jewel(0, 12.9, 0, .32, .7, .32, C.GLINT);
  });
  world('StarwoodTree', { smooth: 50, tint: '46599A', kind: 'tree' }, kit => {
    kit.tube([[0, -.1, 0], [.35, 2.5, 0], [-.2, 5.4, .2], [.25, 8.2, -.1], [0, 10.6, 0]], [.7, .52, .42, .32, .18], { n: 7, color: barkBands(61, C.INK, C.NAVY), capStart: true });
    roots(kit, 5, .7, .8, 63, C.INK, .3);
    const platters = [[3.6, 4.6, .3, 0], [3.0, 6.8, -.25, 1], [2.3, 8.9, .2, 2], [1.4, 10.7, 0, 3]];
    for (const [r, y, dx, t] of platters) {
      kit.group({ pos: [dx, y, 0] }, () => kit.lathe([[.3, -.35], [r * .75, -.42], [r, -.05], [r * .78, .32], [r * .3, .52], [0, .58]], {
        n: 11, phase: t * .5, capStart: true, capColor: TINT_DARK, jitter: (level, i) => level >= 1 && level <= 3 ? (1 + (hash(i, t, 64) - .5) * .22) : 1,
        color: (level, i) => level <= 1 ? TINT_DARK : level === 2 ? TINT : (hash(i, t, 65) < .35 ? TINT_LIGHT : TINT),
      }));
      for (let s = 0; s < 3 + t; s++) {
        const a = s * 2.4 + t, rr = r * (.35 + hash(s, t, 66) * .4);
        kit.jewel(dx + Math.cos(a) * rr, y + .62, Math.sin(a) * rr, .16, .3, .16, C.FLAME);
      }
    }
    kit.jewel(0, 11.9, 0, .38, .7, .38, C.FLAME);
  });
  world('AetherheartTree', { smooth: 50, tint: 'E8D98E', kind: 'tree' }, kit => {
    kit.lathe([[2.1, 0], [1.55, .8], [1.25, 2.5], [1.15, 5], [1.3, 7.2], [.9, 8.6]], { n: 10, capStart: true, color: barkBands(71, C.BARK, C.BARK_DARK), jitter: jitterOf(72, .1) });
    // Arching roots that lift the trunk off the island.
    for (let i = 0; i < 6; i++) {
      const a = i * PI / 3 + .3, r = 3.4 + hash(i, 73, 1);
      kit.tube([[Math.cos(a) * .9, 2.4, Math.sin(a) * .9], [Math.cos(a) * 2.2, 2.2, Math.sin(a) * 2.2], [Math.cos(a) * r, .8, Math.sin(a) * r], [Math.cos(a) * (r + .5), -.1, Math.sin(a) * (r + .5)]], [.55, .45, .34, .22], { n: 6, color: C.BARK });
    }
    // The heart: a glowing crystal seated in a bark hollow on the front.
    kit.group({ pos: [0, 3.6, -1.08] }, () => {
      kit.ring(.62, .22, .32, C.BARK_DARK, 10);
      kit.jewel(0, 0, -.1, .5, .72, .3, TINT_LIGHT);
      kit.jewel(0, 0, -.18, .26, .38, .16, C.GLINT);
    });
    const limbs = [[3.2, 9.6, 0], [-3.0, 9.8, .8], [.6, 10.3, 3.0], [-.4, 10.2, -3.0]];
    for (const [x, y, z] of limbs) kit.tube([[0, 7.8, 0], [x * .5, y - .6, z * .5], [x, y, z]], [.55, .38, .2], { n: 6, color: C.BARK });
    kit.blob(0, 11.6, 0, 4.4, 2.6, 4.4, { sub: 2, amount: .1, seed: 74, squash: .55, color: foliage(74) });
    limbs.forEach(([x, y, z], i) => kit.blob(x * 1.05, y + .5, z * 1.05, 2.1, 1.5, 2.1, { sub: 1, amount: .16, seed: 80 + i, squash: .6, color: foliage(80 + i) }));
    for (let i = 0; i < 8; i++) { const a = i * PI / 4 + .2; kit.jewel(Math.cos(a) * 3.9, 9.0 - hash(i, 75, 1) * .6, Math.sin(a) * 3.9, .2, .42, .2, C.FLAME) }
  });
  world('MeadowTree', { smooth: 55, tint: '6BAF5A', kind: 'tree' }, kit => {
    kit.tube([[0, -.1, 0], [.1, 2, 0], [0, 3.6, .1]], [.55, .42, .36], { n: 7, color: barkBands(91), capStart: true });
    roots(kit, 4, .5, .7, 92, C.BARK, .26);
    kit.tube([[0, 3.2, 0], [1.1, 4.4, .2], [1.7, 5.4, .3]], [.24, .17, .1], { n: 5, color: C.BARK });
    kit.tube([[0, 3.4, 0], [-1, 4.6, -.3], [-1.5, 5.6, -.4]], [.24, .17, .1], { n: 5, color: C.BARK });
    kit.blob(0, 6.3, 0, 2.6, 2.1, 2.5, { sub: 1, amount: .12, seed: 93, squash: .7, color: foliage(93) });
    kit.blob(1.8, 5.6, .4, 1.6, 1.3, 1.6, { sub: 1, amount: .14, seed: 94, squash: .7, color: foliage(94) });
    kit.blob(-1.7, 5.7, -.4, 1.7, 1.35, 1.6, { sub: 1, amount: .14, seed: 95, squash: .7, color: foliage(95) });
    for (let i = 0; i < 5; i++) { const a = i * 1.3; kit.jewel(Math.cos(a) * 2.1, 5.4 + hash(i, 96, 1), Math.sin(a) * 2.1, .16, .16, .16, C.ROSE) }
  });

  // -------------------------------------------------------------------------
  // Rock and cliff pieces (flat-shaded facets).
  // -------------------------------------------------------------------------
  world('Boulder', { smooth: 0, kind: 'rock' }, kit => {
    kit.blob(0, 1.3, 0, 2.2, 1.6, 1.9, { sub: 2, amount: .14, seed: 101, squash: .55, color: rock(101) });
  });
  world('RockCluster', { smooth: 0, kind: 'rock' }, kit => {
    kit.blob(0, 1.1, 0, 1.9, 1.5, 1.7, { sub: 2, amount: .15, seed: 111, squash: .5, color: rock(111) });
    kit.blob(1.9, .6, .7, 1.1, .85, 1.0, { sub: 1, amount: .18, seed: 112, squash: .5, color: rock(112) });
    kit.blob(-1.6, .5, -.9, .9, .7, .9, { sub: 1, amount: .2, seed: 113, squash: .5, color: rock(113) });
    kit.blob(.6, .3, -1.6, .6, .45, .55, { sub: 1, amount: .2, seed: 114, squash: .5, color: rock(114, false) });
  });
  world('CliffPiece', { smooth: 0, kind: 'rock' }, kit => {
    // Columnar basalt: hexagonal columns with slanted, mossy tops.
    const columns = [[0, 0, 6.2], [1.15, .6, 5.1], [-1.1, .5, 5.6], [.1, 1.3, 4.4], [1.1, -.8, 4.2], [-1.0, -.7, 4.9], [-2.1, .2, 3.6], [2.2, -.1, 3.3], [.05, -1.4, 3.0], [-.9, 1.6, 3.8], [1.4, 1.6, 2.6]];
    columns.forEach(([x, z, h], i) => kit.group({ pos: [x, 0, z] }, () => kit.lathe([[.68, -.4], [.66, h * .5], [.64, h]], {
      n: 6, phase: .25, capStart: true, capEnd: true, lift: (level, k) => level === 2 ? (Math.cos(k * PI / 3 + i) * .35) : 0,
      color: (level, k) => level === 3 ? (hash(i, k, 120) < .6 ? C.MOSS : C.STONE_LIGHT) : (hash(level, k + i * 7, 121) < .35 ? C.STONE_DARK : k % 2 ? C.STONE : C.STONE_LIGHT),
    })));
    kit.blob(0, -.1, 0, 3.4, 1.0, 3.0, { sub: 1, amount: .2, seed: 122, squash: .3, color: rock(122) });
  });

  // -------------------------------------------------------------------------
  // Ore veins per tier: tinted crystal clusters seated in a rock bed.
  // Tier 1 copper/aetherite, 2 brassite/sunsteel, 3 voidstone/starmetal, 4 prismite/celestium.
  // -------------------------------------------------------------------------
  world('OreVein1', { smooth: 25, tint: 'B87333', kind: 'ore' }, kit => {
    rockBed(kit, 1.9, 1.0, 1.6, 131, 2);
    crystal(kit, .1, .7, 0, .1, -.15, 1.5, .26, 1);
    crystal(kit, .7, .5, .4, .3, -.6, 1.0, .2, 2);
    crystal(kit, -.6, .5, .3, .35, .55, 1.1, .2, 3);
  });
  world('OreVein2', { smooth: 25, tint: 'D4A84B', kind: 'ore' }, kit => {
    rockBed(kit, 2.3, 1.3, 2.0, 141, 2);
    for (const [x, z, rx, rz, len, r, s] of [[0, 0, 0, 0, 2.2, .34, 1], [.9, .4, .2, -.55, 1.5, .26, 2], [-.85, .35, .3, .55, 1.6, .26, 3], [.3, -.8, -.6, -.2, 1.3, .22, 4], [-.4, -.7, -.5, .35, 1.1, .2, 5]])
      crystal(kit, x, .95, z, rx, rz, len, r, s);
  });
  world('OreVein3', { smooth: 25, tint: '5B3F8C', kind: 'ore' }, kit => {
    rockBed(kit, 2.6, 1.4, 2.3, 151, 2);
    for (const [x, z, rx, rz, len, r, s] of [[0, 0, 0, .05, 3.0, .44, 1], [1.1, .5, .2, -.5, 2.0, .32, 2], [-1.1, .4, .25, .5, 2.2, .32, 3], [.4, -1.0, -.55, -.2, 1.8, .3, 4], [-.6, -.9, -.5, .35, 1.5, .26, 5], [1.3, -.6, -.3, -.7, 1.2, .22, 6], [-1.5, -.2, 0, .8, 1.1, .22, 7]])
      crystal(kit, x, 1.0, z, rx, rz, len, r, s);
    kit.ring(1.6, .18, .12, TINT_LIGHT, 14, PI / 2, 0, PI * 2, 1.25);
  });
  world('OreVein4', { smooth: 25, tint: 'E86FB8', kind: 'ore' }, kit => {
    rockBed(kit, 3.0, 1.5, 2.7, 161, 2);
    for (const [x, z, rx, rz, len, r, s] of [[0, 0, 0, 0, 4.2, .58, 1], [1.3, .6, .2, -.45, 2.6, .38, 2], [-1.3, .5, .25, .45, 2.8, .38, 3], [.5, -1.2, -.5, -.2, 2.3, .34, 4], [-.7, -1.1, -.45, .3, 2.0, .3, 5], [1.6, -.7, -.3, -.65, 1.6, .26, 6], [-1.8, -.3, 0, .75, 1.5, .26, 7], [.2, 1.4, .6, .1, 1.7, .28, 8], [-.9, 1.3, .5, .5, 1.3, .22, 9]])
      crystal(kit, x, 1.05, z, rx, rz, len, r, s);
    for (let i = 0; i < 5; i++) { const a = i * 2 * PI / 5; kit.jewel(Math.cos(a) * 2.0, 4.0 + (i % 2) * .5, Math.sin(a) * 2.0, .18, .42, .18, i % 2 ? TINT_LIGHT : C.GLINT) }
  });

  // -------------------------------------------------------------------------
  // Crops (soil mound + plants). Tint = produce colour.
  // -------------------------------------------------------------------------
  const soil = kit => {
    kit.bevelBox(0, .22, 0, 3.0, .44, 2.2, .14, { top: C.SOIL, side: C.SOIL, bevel: C.SOIL, bottom: C.BARK_DARK });
    for (const z of [-.55, .55]) kit.lathe([[.12, .44], [.12, .5]], { n: 4, sx: 11, color: C.BARK_DARK, phase: PI / 4, capEnd: true, capStart: true, wobble: () => [0, z] });
  };
  world('CropWheat', { smooth: 40, tint: 'E9C46A', kind: 'crop' }, kit => {
    soil(kit);
    for (let i = 0; i < 10; i++) {
      const x = -1.15 + (i % 5) * .57 + (hash(i, 171, 1) - .5) * .2, z = (i < 5 ? -.55 : .55) + (hash(i, 171, 2) - .5) * .2, h = 1.9 + hash(i, 171, 3) * .5, lean = (hash(i, 171, 4) - .5) * .5;
      kit.tube([[x, .4, z], [x + lean * .3, .4 + h * .5, z], [x + lean, .4 + h, z + lean * .3]], [.05, .045, .035], { n: 4, color: C.LEAF });
      kit.group({ pos: [x + lean, .4 + h, z + lean * .3], rot: [0, i, lean * .5] }, () => kit.lathe([[.06, -.05], [.14, .2], [.13, .55], [0, .8]], { n: 5, color: (l, k) => k % 2 ? TINT : TINT_DARK }));
      kit.group({ pos: [x, .5, z], rot: [0, i * 1.7, .9] }, () => kit.jewel(0, .35, 0, .05, .4, .12, C.LEAF));
    }
  });
  world('CropGlowcap', { smooth: 45, tint: 'F4A261', kind: 'crop' }, kit => {
    soil(kit);
    for (const [x, z, s, i] of [[-.8, -.4, 1.1, 0], [.35, -.5, .8, 1], [.9, .45, 1.0, 2], [-.3, .5, .7, 3], [-1.15, .5, .55, 4]]) kit.group({ pos: [x, .42, z], scale: s, rot: [0, i, (hash(i, 181, 1) - .5) * .3] }, () => {
      kit.lathe([[.2, 0], [.16, .5], [.14, .9], [.18, 1.05]], { n: 7, capStart: true, color: C.CLOTH });
      kit.lathe([[.18, .95], [.62, 1.0], [.58, 1.22], [.36, 1.45], [0, 1.52]], { n: 9, capStart: true, capColor: C.CLOTH, color: (l) => l === 0 ? TINT_DARK : l === 3 ? TINT_LIGHT : TINT });
      for (let k = 0; k < 3; k++) { const a = k * 2.1 + i; kit.jewel(Math.cos(a) * .32, 1.38, Math.sin(a) * .32, .08, .04, .08, C.GLINT) }
    });
  });
  world('CropBloom', { smooth: 40, tint: 'B8C0FF', kind: 'crop' }, kit => {
    soil(kit);
    for (const [x, z, h, i] of [[-.85, -.4, 1.6, 0], [.4, -.45, 1.3, 1], [.95, .45, 1.8, 2], [-.4, .5, 1.2, 3]]) {
      kit.tube([[x, .4, z], [x + .1, .4 + h * .6, z], [x, .4 + h, z]], [.05, .045, .04], { n: 4, color: C.LEAF });
      for (let k = 0; k < 3; k++) kit.group({ pos: [x, .55, z], rot: [0, k * 2.1 + i, .95] }, () => kit.jewel(0, .32, 0, .05, .38, .14, k % 2 ? C.LEAF : C.LEAF_DARK));
      kit.group({ pos: [x, .4 + h, z], rot: [.3, i, 0] }, () => {
        for (let p = 0; p < 6; p++) kit.group({ rot: [0, p * PI / 3, .9] }, () => kit.jewel(0, .32, 0, .17, .34, .06, p % 2 ? TINT : TINT_LIGHT));
        kit.jewel(0, .06, 0, .14, .12, .14, C.FLAME);
      });
    }
  });
  world('CropBush', { smooth: 45, tint: 'FFE66D', kind: 'crop' }, kit => {
    soil(kit);
    kit.blob(-.4, 1.15, 0, 1.0, .85, .9, { sub: 1, amount: .2, seed: 191, squash: .6, color: (n, m, i) => n[1] > .4 ? C.LEAF : hash(i, 191, 1) < .5 ? C.LEAF_DARK : C.LEAF });
    kit.blob(.6, 1.0, .1, .85, .7, .8, { sub: 1, amount: .2, seed: 192, squash: .6, color: (n, m, i) => n[1] > .4 ? C.LEAF : hash(i, 192, 1) < .5 ? C.LEAF_DARK : C.LEAF });
    for (let i = 0; i < 9; i++) {
      const a = i * 2.3, r = .75 + hash(i, 193, 1) * .25, x = (i % 2 ? .6 : -.4) + Math.cos(a) * r * .8, z = Math.sin(a) * r * .8;
      kit.group({ pos: [x, .9 + hash(i, 193, 2) * .7, z], rot: [0, a, 0] }, () => { kit.jewel(0, 0, 0, .2, .14, .2, TINT); kit.jewel(0, 0, 0, .14, .2, .07, TINT_LIGHT) });
    }
  });

  // -------------------------------------------------------------------------
  // Fishing buoy, lamps and lanterns.
  // -------------------------------------------------------------------------
  world('FishingBuoy', { smooth: 45, tint: 'C15557', kind: 'water' }, kit => {
    kit.lathe([[0, -.6], [.55, -.45], [.82, 0], [.75, .5], [.42, .9], [.3, 1.0]], { n: 10, capEnd: true, capColor: C.MARBLE, color: l => l === 2 ? C.MARBLE : l === 0 ? C.IRON : TINT });
    kit.ring(.9, .14, .16, C.STRAW, 14, PI / 2, 0, PI * 2, -.05);
    kit.lathe([[.05, 1.0], [.04, 2.5]], { n: 5, capEnd: true, color: C.IRON });
    kit.prism([[.05, 2.45], [.75, 2.25], [.55, 2.05], [.75, 1.85], [.05, 1.9]], .04, TINT_LIGHT, TINT);
    kit.blob(0, 2.6, 0, .12, .12, .12, { sub: 0, color: C.FLAME });
    kit.ring(1.35, .1, .03, C.GLASS, 16, PI / 2, 0, PI * 2, -.2);
    kit.ring(1.85, .08, .03, C.GLASS, 18, PI / 2, 0, PI * 2, -.22);
  });
  const lanternCage = (kit, glow = C.FLAME) => {
    kit.lathe([[.38, -.5], [.42, -.42], [.42, -.34], [.3, -.3]], { n: 6, capStart: true, color: C.IRON });
    kit.lathe([[.27, -.32], [.3, .1], [.24, .42]], { n: 6, capStart: true, capEnd: true, color: l => l === 0 ? glow : C.AMBER });
    for (let i = 0; i < 6; i++) { const a = i * PI / 3; kit.box(Math.cos(a) * .33, .05, Math.sin(a) * .33, .05, .8, .05, C.IRON) }
    kit.lathe([[.34, .42], [.46, .48], [.3, .72], [.08, .9], [0, .95]], { n: 6, capStart: true, color: C.IRON });
    kit.ring(.1, .04, .04, C.IRON, 8, 0, 0, PI * 2, 1.04);
  };
  world('StreetLamp', { smooth: 40, kind: 'lamp' }, kit => {
    kit.bevelBox(0, .3, 0, 1.2, .6, 1.2, .1, C.STONE);
    kit.lathe([[.38, .6], [.36, .9], [.22, 1.1], [.2, 1.5], [.16, 6.2], [.22, 6.4], [.24, 6.6], [.1, 6.8], [0, 7.05]], { n: 8, capStart: true, color: l => l === 5 || l === 6 ? C.BRASS : C.IRON });
    kit.tube([[0, 6.0, 0], [.5, 6.5, 0], [1.1, 6.6, 0], [1.5, 6.35, 0]], [.07, .07, .07, .06], { n: 5, color: C.IRON });
    kit.tube([[0, 5.3, 0], [.45, 5.6, 0], [.9, 6.25, 0]], [.05, .05, .05], { n: 4, color: C.IRON });
    kit.group({ pos: [1.5, 5.6, 0] }, () => lanternCage(kit));
  });
  world('LampPost', { smooth: 50, tint: 'FFE08A', kind: 'lamp' }, kit => {
    kit.lathe([[.45, 0], [.45, .18], [.3, .3], [.16, .55], [.13, 2.6], [.2, 2.75], [.25, 2.85]], { n: 8, capStart: true, capEnd: true, color: l => l >= 4 ? C.BRASS : C.IRON });
    kit.blob(0, 3.2, 0, .45, .45, .45, { sub: 1, color: (n) => n[1] > .3 ? TINT_LIGHT : TINT });
    kit.lathe([[.18, 3.55], [.26, 3.62], [.1, 3.8], [0, 3.88]], { n: 8, capStart: true, color: C.BRASS });
  });
  world('HangingLantern', { smooth: 40, kind: 'lamp' }, kit => {
    lanternCage(kit);
    kit.tube([[0, 1.04, 0], [0, 1.6, 0]], .025, { n: 4, color: C.IRON });
    kit.ring(.16, .05, .05, C.IRON, 8, 0, 0, PI * 2, 1.75);
  });

  // -------------------------------------------------------------------------
  // Crafting stations.
  // -------------------------------------------------------------------------
  const anvil = (kit, x, y, z, s = 1) => kit.group({ pos: [x, y, z], scale: s }, () => {
    kit.lathe([[.5, 0], [.44, .2], [.4, .6], [.42, .7]], { n: 10, capStart: true, capEnd: true, capColor: C.PLANK, color: barkBands(17), jitter: jitterOf(18, .07) });
    kit.slab(0, .82, 0, .55, .4, .32, .26, .24, C.IRON);
    kit.bevelBox(0, 1.07, 0, 1.0, .26, .44, .05, C.IRON);
    kit.group({ pos: [.5, 1.07, 0], rot: [0, 0, -PI / 2] }, () => kit.lathe([[.18, 0], [.1, .35], [0, .55]], { n: 5, capStart: true, color: C.IRON, sz: 1.2 }));
    kit.group({ pos: [-.15, 1.28, .05], rot: [0, .5, 0] }, () => {
      kit.bevelBox(0, .06, 0, .34, .16, .16, .03, C.IRON);
      kit.tube([[0, .06, 0], [0, .06, .75]], [.035, .03], { n: 5, color: C.PLANK });
    });
  });
  world('Forge', { smooth: 30, kind: 'station' }, kit => {
    kit.bevelBox(0, .9, 0, 3.6, 1.8, 2.4, .18, { top: C.STONE_LIGHT, side: C.STONE, bevel: C.STONE_LIGHT, bottom: C.STONE_DARK });
    kit.bevelBox(0, 1.95, .1, 3.2, .3, 2.1, .08, C.STONE_DARK);
    // Glowing firebox mouth and coal bed.
    kit.bevelBox(0, .95, -1.12, 1.6, 1.0, .16, .06, C.INK);
    kit.bevelBox(0, .95, -1.16, 1.3, .7, .1, .05, C.EMBER);
    for (let i = 0; i < 5; i++) kit.jewel(-.45 + i * .22, 1.05 + (i % 2) * .12, -1.24, .1, .22 + (i % 3) * .06, .05, i % 2 ? C.FLAME : C.EMBER);
    kit.prism([[-1.0, 1.55], [0, 1.95], [1.0, 1.55]], .2, C.STONE_LIGHT, C.STONE, -1.1);
    // Chimney hood and stack.
    kit.group({ pos: [0, 2.1, .3] }, () => kit.lathe([[1.5, 0], [1.2, .6], [.55, 1.4], [.5, 3.4], [.62, 3.55], [.62, 3.75]], { n: 4, phase: PI / 4, capStart: true, capEnd: true, color: l => l >= 3 ? C.STONE_DARK : C.STONE, sz: .8 }));
    kit.blob(0, 6.0, .3, .35, .25, .35, { sub: 1, amount: .2, seed: 201, color: C.STONE_LIGHT });
    // Bellows and an anvil beside the forge.
    kit.group({ pos: [2.2, .8, .4], rot: [0, 0, .2] }, () => {
      kit.prism([[-.5, 0], [.6, .25], [.6, -.25]], .7, C.CRIMSON, C.BARK);
      kit.box(-.75, 0, 0, .5, .08, .1, C.PLANK);
    });
    kit.bevelBox(2.2, .3, .4, .8, .6, .8, .06, C.PLANK);
    anvil(kit, -2.6, 0, -.6, 1);
    kit.blob(1.2, .1, -1.6, .5, .25, .45, { sub: 1, amount: .3, seed: 202, color: C.INK });
  });
  world('Anvil', { smooth: 30, kind: 'station' }, kit => anvil(kit, 0, 0, 0, 1.4));
  world('Hearth', { smooth: 40, kind: 'station' }, kit => {
    for (let i = 0; i < 11; i++) { const a = i * 2 * PI / 11; kit.blob(Math.cos(a) * 1.2, .22, Math.sin(a) * 1.2, .34, .26, .3, { sub: 0, amount: .2, seed: 210 + i, color: rock(210 + i, false) }) }
    for (let i = 0; i < 4; i++) { const a = i * PI / 2 + .4; kit.tube([[Math.cos(a) * .9, .15, Math.sin(a) * .9], [Math.cos(a) * .1, .55, Math.sin(a) * .1]], [.12, .1], { n: 5, color: C.BARK, capColor: C.PLANK }) }
    kit.lathe([[.6, .1], [.35, .5], [.2, 1.0], [0, 1.4]], { n: 7, capStart: true, color: (l, i) => l === 0 ? C.EMBER : (i % 2 ? C.FLAME : C.EMBER), jitter: jitterOf(219, .2) });
    for (const a of [0, 2.1, 4.2]) kit.tube([[Math.cos(a) * 1.3, 0, Math.sin(a) * 1.3], [Math.cos(a) * .25, 2.3, Math.sin(a) * .25], [0, 2.5, 0]], .06, { n: 4, color: C.IRON });
    kit.tube([[0, 2.45, 0], [0, 1.9, 0]], .025, { n: 4, color: C.IRON });
    kit.lathe([[0, 1.3], [.35, 1.35], [.48, 1.6], [.46, 1.85], [.4, 1.92]], { n: 9, color: C.IRON, capEnd: true, capColor: C.CLOTH });
  });
  world('Cauldron', { smooth: 45, tint: '6BD18A', kind: 'station' }, kit => {
    kit.lathe([[0, .45], [.55, .5], [.95, .8], [1.1, 1.3], [1.0, 1.75], [1.12, 1.85], [1.12, 1.95]], { n: 12, color: l => l === 5 ? C.BRASS : C.IRON });
    kit.lathe([[.98, 1.75], [.98, 1.82]], { n: 12, capEnd: true, capColor: TINT, color: TINT_DARK });
    for (let i = 0; i < 5; i++) { const a = i * 1.3; kit.blob(Math.cos(a) * .45, 1.9, Math.sin(a) * .45, .14 + (i % 2) * .06, .1, .14, { sub: 0, color: i % 2 ? TINT_LIGHT : TINT }) }
    for (let i = 0; i < 3; i++) { const a = i * 2 * PI / 3; kit.tube([[Math.cos(a) * .75, .7, Math.sin(a) * .75], [Math.cos(a) * 1.0, 0, Math.sin(a) * 1.0]], [.09, .07], { n: 5, color: C.IRON }) }
    for (const s of [-1, 1]) kit.group({ pos: [s * 1.12, 1.6, 0], rot: [0, PI / 2, 0] }, () => kit.ring(.18, .06, .06, C.BRASS, 8));
    for (let i = 0; i < 3; i++) { const a = i * 2.1 + .5; kit.tube([[Math.cos(a) * .6, .12, Math.sin(a) * .6], [-Math.cos(a) * .4, .2, -Math.sin(a) * .4]], .1, { n: 5, color: C.BARK, capColor: C.EMBER }) }
  });
  world('Workbench', { smooth: 30, kind: 'station' }, kit => {
    kit.bevelBox(0, 1.75, 0, 4.0, .22, 1.8, .06, { top: C.PLANK, side: C.BARK, bevel: C.PLANK, bottom: C.BARK });
    for (const x of [-1.75, 1.75]) for (const z of [-.7, .7]) kit.bevelBox(x, .82, z, .24, 1.64, .24, .04, C.BARK);
    for (const x of [-1.75, 1.75]) kit.box(x, .4, 0, .16, .16, 1.3, C.BARK);
    kit.bevelBox(0, .55, 0, 3.6, .1, 1.4, .03, C.PLANK);
    // Vise, mallet, saw, planks and a small crate.
    kit.bevelBox(-1.55, 2.05, -.8, .5, .4, .3, .05, C.IRON);
    kit.tube([[-1.55, 2.05, -1.05], [-1.55, 2.05, -1.35]], .04, { n: 4, color: C.BRASS });
    kit.group({ pos: [.4, 1.9, -.2], rot: [0, .6, 0] }, () => { kit.bevelBox(0, .08, 0, .5, .24, .28, .05, C.BARK); kit.tube([[0, .08, 0], [0, .08, -.9]], .045, { n: 5, color: C.PLANK }) });
    kit.group({ pos: [1.3, 1.88, .25], rot: [0, -.3, 0] }, () => { kit.prism([[-.7, 0], [.55, 0], [.55, .32]], .03, C.STONE_LIGHT, C.IRON); kit.bevelBox(.75, .16, 0, .3, .36, .08, .03, C.PLANK) });
    for (let i = 0; i < 3; i++) kit.bevelBox(-.4 + i * .1, .66 + i * .1, .1 - i * .05, 2.4 - i * .3, .1, .4, .02, i % 2 ? C.PLANK : C.STRAW);
    kit.bevelBox(-.6, 2.06, .35, .7, .4, .55, .04, { top: C.STRAW, side: C.PLANK, bevel: C.BARK, bottom: C.BARK });
  });

  // -------------------------------------------------------------------------
  // Bridge pieces, statues, warp beacon, market stall, crates and barrels.
  // -------------------------------------------------------------------------
  world('BridgePost', { smooth: 30, kind: 'bridge' }, kit => {
    kit.bevelBox(0, 1.5, 0, .7, 3.0, .7, .08, C.PLANK);
    kit.bevelBox(0, .12, 0, .9, .24, .9, .05, C.BARK);
    for (const y of [.9, 2.3]) kit.ring(.5, .1, .12, C.STRAW, 12, PI / 2, 0, PI * 2, y);
    for (const y of [.6, 2.6]) kit.bevelBox(0, y, 0, .78, .08, .78, .02, C.BARK);
    kit.lathe([[.46, 3.0], [.48, 3.12], [.3, 3.3], [.16, 3.55], [0, 3.85]], { n: 8, capStart: true, color: C.BRASS });
    kit.jewel(0, 3.95, 0, .1, .14, .1, C.GLINT);
  });
  world('BridgeRail', { smooth: 35, kind: 'bridge' }, kit => {
    kit.bevelBox(0, 2.1, 0, 8.0, .24, .32, .06, { top: C.PLANK, side: C.BARK, bevel: C.PLANK, bottom: C.BARK });
    kit.bevelBox(0, .3, 0, 8.0, .18, .26, .05, C.BARK);
    for (let i = 0; i < 9; i++) kit.group({ pos: [-3.6 + i * .9, 0, 0] }, () => kit.lathe([[.1, .38], [.13, .55], [.08, .8], [.14, 1.2], [.08, 1.6], [.12, 1.85], [.1, 2.0]], { n: 6, color: l => l === 3 ? C.BRASS : C.PLANK }));
  });
  world('Statue', { smooth: 45, tint: '9DF3D7', kind: 'statue' }, kit => {
    kit.bevelBox(0, .3, 0, 2.6, .6, 2.6, .1, C.STONE);
    kit.bevelBox(0, 1.0, 0, 2.0, .8, 2.0, .08, { top: C.MARBLE, side: C.MARBLE, bevel: C.BRASS, bottom: C.STONE });
    kit.bevelBox(0, 1.0, -1.01, 1.2, .3, .06, .02, C.BRASS);
    // Robed sky-warden holding a tinted orb aloft.
    kit.lathe([[.85, 1.4], [.92, 1.7], [.7, 2.6], [.52, 3.4], [.5, 3.9], [.36, 4.25]], { n: 12, capStart: true, color: l => l === 0 ? C.STONE_LIGHT : C.MARBLE, jitter: (l, i) => l <= 1 ? 1 + (i % 2) * .07 : 1 });
    kit.blob(0, 4.55, -.05, .3, .36, .3, { sub: 1, color: C.MARBLE });
    kit.lathe([[.4, 4.15], [.42, 4.5], [.32, 4.95], [0, 5.12]], { n: 10, color: C.STONE_LIGHT, wobble: (l) => [0, l * .04] });
    kit.tube([[.42, 3.9, 0], [.75, 4.3, -.15], [.6, 5.0, -.3]], [.15, .13, .11], { n: 6, color: C.MARBLE });
    kit.tube([[-.42, 3.9, 0], [-.65, 3.3, -.3], [-.45, 2.9, -.55]], [.15, .13, .11], { n: 6, color: C.MARBLE });
    kit.blob(.6, 5.35, -.3, .32, .32, .32, { sub: 1, color: n => n[1] > .2 ? TINT_LIGHT : TINT });
    kit.tube([[-.5, 1.42, -.6], [-.45, 3.0, -.56], [-.4, 4.6, -.5]], .05, { n: 5, color: C.BRASS });
    kit.jewel(-.4, 4.75, -.5, .12, .2, .12, TINT);
  });
  world('Obelisk', { smooth: 0, tint: '9DF3D7', kind: 'statue' }, kit => {
    kit.bevelBox(0, .2, 0, 2.4, .4, 2.4, .06, C.STONE);
    kit.bevelBox(0, .6, 0, 1.8, .4, 1.8, .06, C.STONE_LIGHT);
    kit.lathe([[.85, .8], [.7, 5.6], [0, 6.4]], { n: 4, phase: PI / 4, sx: 1, color: (l, i) => l === 1 ? C.BRASS : C.STONE_LIGHT, capStart: true });
    for (let i = 0; i < 4; i++) kit.group({ rot: [0, i * PI / 2, 0] }, () => {
      for (let k = 0; k < 4; k++) kit.box(0, 1.6 + k * .9, -.6 + k * .02, .28 - k * .02, .4, .04, k % 2 ? TINT : TINT_LIGHT);
    });
  });
  world('WarpBeacon', { smooth: 40, tint: '9DF3D7', kind: 'warp' }, kit => {
    kit.lathe([[2.4, 0], [2.4, .25], [2.1, .35], [1.7, .55], [1.7, .62]], { n: 14, capStart: true, capEnd: true, capColor: C.MARBLE, color: l => l === 2 ? C.BRASS : C.STONE });
    kit.ring(1.25, .14, .04, TINT, 16, PI / 2, 0, PI * 2, .64);
    for (let i = 0; i < 6; i++) { const a = i * PI / 3 + PI / 6; kit.group({ pos: [Math.cos(a) * 2.05, .65, Math.sin(a) * 2.05], rot: [0, -a, 0] }, () => { kit.bevelBox(0, .3, 0, .36, .6, .3, .05, C.STONE_LIGHT); kit.box(0, .38, -.16, .14, .3, .04, TINT) }) }
    // Split brass arms forming an open ring with a hovering crystal.
    for (const s of [-1, 1]) {
      const arc = [];
      for (let k = 0; k <= 8; k++) { const a = PI * (.06 + k * .11); arc.push([s * Math.sin(a) * 1.7, .6 + 2.4 - Math.cos(a) * 2.4 * .95, 0]) }
      kit.tube(arc, i => .2 - i * .012, { n: 6, color: C.BRASS });
      kit.jewel(s * Math.sin(PI * .94) * 1.7, .6 + 2.4 - Math.cos(PI * .94) * 2.28 + .25, 0, .14, .3, .14, TINT_LIGHT);
    }
    kit.group({ pos: [0, 2.9, 0] }, () => {
      kit.lathe([[0, -.9], [.42, -.2], [.42, .2], [0, .9]], { n: 6, color: (l, i) => i % 2 ? TINT : TINT_LIGHT });
    });
    for (let i = 0; i < 4; i++) { const a = i * PI / 2 + .4; kit.jewel(Math.cos(a) * .9, 2.9 + (i % 2 ? .4 : -.4), Math.sin(a) * .9, .1, .22, .1, C.GLINT) }
  });
  world('MarketStall', { smooth: 30, tint: 'C15557', kind: 'stall' }, kit => {
    kit.bevelBox(0, .6, 0, 4.2, 1.2, 1.6, .06, { top: C.PLANK, side: C.PLANK, bevel: C.BARK, bottom: C.BARK });
    for (let i = 0; i < 5; i++) kit.box(-1.68 + i * .84, .6, -.81, .06, 1.1, .04, C.BARK);
    kit.bevelBox(0, 1.24, -.1, 4.4, .1, 1.9, .03, C.BARK);
    for (const x of [-2.05, 2.05]) for (const z of [-.85, .85]) kit.bevelBox(x, 1.65 + (z > 0 ? .3 : 0), z, .16, 3.3 + (z > 0 ? .6 : 0), .16, .03, C.BARK);
    // Striped canopy sloping toward the front with a scalloped valance.
    kit.group({ pos: [0, 3.55, 0], rot: [-.32, 0, 0] }, () => {
      for (let i = 0; i < 7; i++) kit.box(-2.1 + i * .7 + .35, 0, 0, .7, .08, 2.3, i % 2 ? C.CLOTH : TINT);
    });
    for (let i = 0; i < 7; i++) kit.group({ pos: [-2.1 + i * .7 + .35, 3.17, -1.12], rot: [-.32, 0, 0] }, () => kit.prism([[-.35, 0], [.35, 0], [0, -.38]], .04, i % 2 ? C.CLOTH : TINT, i % 2 ? C.CLOTH : TINT_DARK));
    // Produce crates on the counter.
    const produce = [C.ROSE, C.FLAME, C.LEAF];
    for (let c = 0; c < 3; c++) {
      const x = -1.3 + c * 1.3;
      kit.bevelBox(x, 1.45, -.2, 1.0, .35, .8, .04, { top: C.BARK, side: C.PLANK, bevel: C.BARK, bottom: C.BARK });
      for (let k = 0; k < 4; k++) kit.blob(x - .28 + (k % 2) * .56, 1.68, -.38 + Math.floor(k / 2) * .36, .2, .17, .2, { sub: 0, color: produce[c] });
    }
  });
  world('Crate', { smooth: 0, kind: 'prop' }, kit => {
    kit.bevelBox(0, .75, 0, 1.5, 1.5, 1.5, .05, C.PLANK);
    for (const z of [-.76, .76]) {
      for (const s of [-1, 1]) { kit.box(0, .75 + s * .64, z, 1.56, .2, .06, C.BARK); kit.box(s * .64, .75, z, .2, 1.56, .06, C.BARK) }
      kit.box(0, .75, z, 1.7, .16, .05, C.BARK, PI / 4);
    }
    for (const s of [-1, 1]) for (const x of [-.76, .76]) kit.box(x, .75 + s * .64, 0, .06, .2, 1.56, C.BARK);
  });
  world('Barrel', { smooth: 45, kind: 'prop' }, kit => {
    kit.lathe([[.55, 0], [.68, .4], [.74, .85], [.68, 1.3], [.55, 1.7]], { n: 14, capStart: true, capEnd: true, capColor: C.PLANK, color: (l, i) => i % 3 === 0 ? C.BARK : C.PLANK });
    for (const [y, r] of [[.25, .64], [.62, .735], [1.08, .735], [1.45, .64]]) kit.lathe([[r + .025, y], [r + .025, y + .08]], { n: 14, color: C.IRON, capStart: true, capEnd: true });
  });

  // -------------------------------------------------------------------------
  // Signs. Signboard / SignboardPosted fit their text board (fit box) so the
  // frame wraps the original board part, which stays as the SurfaceGui surface.
  // -------------------------------------------------------------------------
  const BOARD = [12, 3.1, .32];
  const board = kit => {
    const [w, h, d] = BOARD, f = .34;
    kit.box(0, 0, 0, w, h, d * .8, C.INK);
    for (const s of [-1, 1]) {
      kit.bevelBox(0, s * (h / 2 + f / 2), 0, w + 2 * f, f, d + .14, .06, { top: C.PLANK, side: C.BARK, bevel: C.PLANK, bottom: C.BARK, front: C.PLANK });
      kit.bevelBox(s * (w / 2 + f / 2), 0, 0, f, h, d + .14, .06, { top: C.PLANK, side: C.PLANK, bevel: C.PLANK, bottom: C.PLANK });
      for (const t of [-1, 1]) {
        kit.bevelBox(s * (w / 2 + f / 2), t * (h / 2 + f / 2), 0, f + .16, f + .16, d + .22, .06, C.BRASS);
        kit.jewel(s * (w / 2 + f / 2), t * (h / 2 + f / 2), -(d + .22) / 2 - .02, .08, .08, .05, C.GLINT);
      }
      for (let k = 1; k <= 3; k++) kit.jewel(s * k * w / 8, h / 2 + f / 2, -(d + .14) / 2 - .02, .06, .06, .04, C.BRASS);
    }
    // Crest: a brass-trimmed arch with a tinted jewel above the top rail.
    kit.prism([[-1.5, 0], [-1.1, .42], [-.4, .7], [.4, .7], [1.1, .42], [1.5, 0]].map(([x, y]) => [x, y + h / 2 + f]), .24, C.PLANK, C.BARK);
    kit.ring(.32, .08, .3, C.BRASS, 10, 0, 0, PI * 2, h / 2 + f + .42);
    kit.jewel(0, h / 2 + f + .42, -.08, .2, .24, .12, TINT);
  };
  const boardFit = [[-BOARD[0] / 2, -BOARD[1] / 2, -BOARD[2] / 2], [BOARD[0] / 2, BOARD[1] / 2, BOARD[2] / 2]];
  world('Signboard', { smooth: 30, tint: '9DF3D7', fit: boardFit, kind: 'sign' }, kit => board(kit));
  world('SignboardPosted', { smooth: 30, tint: '9DF3D7', fit: boardFit, kind: 'sign' }, kit => {
    board(kit);
    for (const s of [-1, 1]) {
      kit.bevelBox(s * 5.3, -2.9, .3, .4, 3.6, .4, .06, C.BARK);
      kit.lathe([[.34, -4.75], [.34, -4.5], [.24, -4.4]], { n: 4, phase: PI / 4, capStart: true, capEnd: true, color: C.BRASS, wobble: () => [s * 5.3, .3] });
    }
  });
  world('SignPost', { smooth: 35, tint: 'C9A24E', kind: 'sign' }, kit => {
    for (let i = 0; i < 5; i++) { const a = i * 2 * PI / 5; kit.blob(Math.cos(a) * .55, .15, Math.sin(a) * .55, .3, .22, .28, { sub: 0, amount: .2, seed: 300 + i, color: rock(300 + i, false) }) }
    kit.lathe([[.24, 0], [.22, 4.8], [.28, 4.95], [.18, 5.15], [0, 5.35]], { n: 8, capStart: true, color: l => l >= 1 ? C.BRASS : C.PLANK, jitter: (l, i) => 1 });
    const arrows = [[4.1, .35, 1], [3.3, -.9, -1], [2.5, 2.4, 1]];
    arrows.forEach(([y, yaw, dir], i) => kit.group({ pos: [0, y, 0], rot: [0, yaw, 0] }, () => {
      const L = 2.7 - i * .2, H = .62;
      const outline = [[-.35, -H / 2], [L - .55, -H / 2], [L - .55, -H / 2 - .14], [L, 0], [L - .55, H / 2 + .14], [L - .55, H / 2], [-.35, H / 2]].map(([x, yy]) => [x * dir + dir * .1, yy]);
      if (dir < 0) outline.reverse();
      kit.prism(outline, .14, C.PLANK, C.BARK);
      kit.group({ pos: [dir * (L - .3), 0, -.08] }, () => kit.jewel(0, 0, 0, .12, .16, .03, TINT));
      kit.box(dir * .9, .2, -.075, L * .55, .05, .02, C.BARK);
      kit.box(dir * .9, -.08, -.075, L * .45, .05, .02, C.BARK);
    }));
  });
  world('Banner', { smooth: 30, tint: 'C15557', kind: 'sign' }, kit => {
    kit.tube([[-1.5, 4.0, 0], [1.5, 4.0, 0]], .07, { n: 6, color: C.PLANK });
    for (const s of [-1, 1]) kit.blob(s * 1.6, 4.0, 0, .13, .13, .13, { sub: 1, color: C.BRASS });
    // Accordion-folded cloth with a swallowtail hem and an emblem.
    const strips = 8, w = 2.6 / strips;
    for (let i = 0; i < strips; i++) {
      const x = -1.3 + w * (i + .5), fold = i % 2 ? .22 : -.22;
      kit.group({ pos: [x, 2.45, 0], rot: [0, fold, 0] }, () => kit.box(0, 0, 0, w * 1.02, 3.0, .05, i % 2 ? TINT_DARK : TINT));
      const tip = i < strips / 2 ? -.7 * (1 - Math.abs(i - 1.5) / 2.2) : -.7 * (1 - Math.abs(i - 5.5) / 2.2);
      kit.group({ pos: [x, .95, 0], rot: [0, fold, 0] }, () => kit.prism([[-w * .51, 0], [w * .51, 0], [w * .51, tip - .2], [-w * .51, tip - .2]], .05, i % 2 ? TINT_DARK : TINT));
    }
    kit.box(0, 3.85, 0, 2.7, .18, .1, C.BRASS);
    kit.group({ pos: [0, 2.6, -.12] }, () => {
      kit.jewel(0, 0, 0, .55, .7, .06, C.BRASS);
      kit.jewel(0, 0, -.03, .32, .42, .05, TINT_LIGHT);
    });
    for (const s of [-1, 1]) kit.tube([[s * 1.2, 4.0, 0], [0, 4.6, 0]], .025, { n: 4, color: C.STRAW });
  });
};
