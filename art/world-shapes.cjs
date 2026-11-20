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
//   along:  authored long axis of a line shape ('Y' or 'Z'); the forge turns it onto the
//           slot box's longest axis (a rope that hangs or spans between two points)
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
  // -------------------------------------------------------------------------
  // Landmarks, harbour and island props. Authored at their world slot sizes
  // (world.server.lua hosts) so the stretch onto each slot box stays close to 1.
  // -------------------------------------------------------------------------
  // Moored skyship: the hull's ShapeOwnsModel box covers deck, mast, sail and the
  // balloon (about 12 x 29.5 x 30, keel at y 0, bow toward -Z).
  world('Skyship', { smooth: 35, tint: 'C15557', kind: 'ship' }, kit => {
    const hullAt = t => {
      const z = -14 + 28 * t;
      const w = Math.max(.35, 4.5 * (t < .55 ? Math.pow(Math.sin(t / .55 * PI / 2), .6) : 1 - .32 * Math.pow((t - .55) / .45, 2)));
      const top = 5 + 1.3 * Math.pow(1 - t, 4) + .7 * Math.pow(t, 4), keel = 1.6 * Math.pow(1 - t, 3) + .9 * Math.pow(t, 4);
      return { z, w, top, keel };
    };
    const N = 10, sections = [];
    for (let s = 0; s <= N; s++) {
      const { z, w, top, keel } = hullAt(s / N), d = top - keel;
      sections.push({ z, points: [[-w, top], [-w * .98, keel + d * .62], [-w * .8, keel + d * .25], [-w * .34, keel], [w * .34, keel], [w * .8, keel + d * .25], [w * .98, keel + d * .62], [w, top]] });
    }
    kit.loft(sections, { color: (s, e) => e === 7 ? C.PLANK : e === 0 || e === 6 ? (s % 3 === 1 ? C.BARK_DARK : C.BARK) : e === 1 || e === 5 ? TINT_DARK : C.BARK_DARK, capColor: C.BARK });
    // Deck, gunwale rails on posts and a brass waterline band.
    kit.bevelBox(0, 5.12, 1, 7.6, .26, 21, .06, { top: C.PLANK, side: C.BARK, bevel: C.STRAW, bottom: C.BARK });
    for (const side of [-1, 1]) {
      const rail = [];
      for (let s = 1; s < N; s++) { const { z, w, top } = hullAt(s / N); rail.push([side * (w - .2), top + .75, z]) }
      kit.tube(rail, .1, { n: 4, color: C.PLANK });
      rail.forEach(([x, y, z], i) => { if (i % 3 === 0) kit.box(x, y - .38, z, .14, .76, .14, C.BARK) });
      const band = [];
      for (let s = 0; s <= N; s++) { const { z, w, top, keel } = hullAt(s / N); band.push([side * w * .99, keel + (top - keel) * .62, z]) }
      kit.tube(band, .09, { n: 4, color: C.BRASS });
    }
    // Stern cabin with lit windows.
    kit.bevelBox(0, 6.25, 10.6, 5.4, 2.1, 4.4, .12, { top: C.BARK, side: C.PLANK, bevel: C.BARK, bottom: C.BARK });
    kit.bevelBox(0, 7.42, 10.6, 6.0, .3, 5.0, .08, TINT_DARK);
    for (const side of [-1, 1]) for (let k = 0; k < 3; k++) kit.box(side * 2.71, 6.4, 9.3 + k * 1.3, .05, .7, .6, C.FLAME);
    kit.box(0, 6.0, 8.38, 1.0, 1.6, .06, C.BARK_DARK);
    // Mast, crow's nest, yards and a bellied square sail (across X).
    kit.lathe([[.45, 5], [.4, 12], [.3, 20.4]], { n: 8, capEnd: true, color: C.BARK });
    kit.lathe([[.5, 16.6], [1.0, 16.8], [1.05, 17.5], [.95, 17.5], [.9, 16.95], [.4, 16.95]], { n: 8, color: l => l >= 2 ? C.BRASS : C.PLANK });
    for (const y of [18.4, 8.8]) kit.tube([[-6, y, -.25], [6, y, -.25]], .17, { n: 6, color: C.PLANK });
    const strips = 6, sw = 11.4 / strips;
    for (let i = 0; i < strips; i++) {
      const x = -5.7 + sw * (i + .5), belly = -.9 * Math.sin(PI * (i + .5) / strips);
      kit.group({ pos: [x, 13.6, belly - .4], rot: [0, (i - (strips - 1) / 2) * .16, 0] }, () => kit.box(0, 0, 0, sw * 1.04, 9.3, .08, i === 2 || i === 3 ? TINT : C.CLOTH));
    }
    // Lifting balloon: striped gores along Z with tail fins, rigged to the rails.
    kit.group({ pos: [0, 24, 0], rot: [PI / 2, 0, 0] }, () => {
      kit.lathe([[0, -8.2], [2.4, -7.4], [4.3, -5.4], [5.5, -1.8], [5.5, 1.6], [4.7, 4.8], [3.0, 7.0], [0, 8.2]], { n: 12, color: (l, i) => i % 2 ? C.CLOTH : TINT });
      for (const a of [0, PI / 2, PI, PI * 1.5]) kit.group({ rot: [0, a, 0] }, () => kit.prism([[2.6, 4.4], [5.0, 6.6], [5.0, 8.0], [1.2, 7.9]], .12, TINT_DARK, C.BRASS));
    });
    kit.lathe([[.0, 18.2], [1.2, 18.35], [1.3, 18.8], [.9, 18.9]], { n: 10, color: C.BRASS });
    for (const [x, z] of [[-3.6, -6], [3.6, -6], [-3.6, 7], [3.6, 7]]) kit.tube([[x * .8, 19.4, z * .8], [x * 1.08, 6.0, z]], .05, { n: 3, color: C.STRAW });
    // Aether sky-fins: ribbed side wings that reach the model box's width.
    for (const side of [-1, 1]) kit.group({ pos: [side * 4.2, 4.2, -1], rot: [PI / 2, 0, side * -.12] }, () => {
      kit.prism([[0, -3.2], [side * 3.6, -1.6], [side * 3.6, .4], [0, 2.6]], .12, TINT_LIGHT, C.BRASS);
      kit.tube([[0, .2, 0], [side * 3.6, -.6, 0]], .08, { n: 4, color: C.BRASS });
    });
    // Bowsprit, rudder, stern propeller and lanterns.
    kit.tube([[0, 5.9, -12.5], [0, 7.4, -15]], [.22, .1], { n: 6, color: C.PLANK });
    kit.bevelBox(0, 2.4, 13.9, .2, 3.2, 1.3, .05, C.BARK);
    kit.group({ pos: [0, 3.4, 14.3], rot: [PI / 2, 0, 0] }, () => kit.lathe([[.25, -.35], [.28, .2], [.12, .45], [0, .55]], { n: 8, capStart: true, color: C.BRASS }));
    for (let b = 0; b < 3; b++) kit.group({ pos: [0, 3.4, 14.45], rot: [0, 0, b * 2 * PI / 3] }, () => kit.jewel(0, .75, 0, .32, .7, .07, C.BRASS));
    for (const side of [-1, 1]) kit.jewel(side * 2.2, 7.9, 12.9, .18, .26, .18, C.FLAME);
  });

  // Shoals lighthouse: footing, striped tower, gallery, an open lantern room (the
  // world's Neon flame shows through) and a domed cap. Cylinder host, 6.8 x 21.4.
  world('Lighthouse', { smooth: 40, tint: 'C15557', kind: 'tower' }, kit => {
    kit.lathe([[3.4, 0], [3.35, 1.1], [3.05, 1.9], [2.5, 2.05]], { n: 12, capStart: true, capEnd: true, jitter: jitterOf(401, .05), color: (l, i) => l === 2 ? C.STONE_LIGHT : hash(l, i, 402) < .35 ? C.STONE_DARK : C.STONE, capColor: C.STONE_DARK });
    kit.lathe([[2.35, 2], [2.3, 5.2], [2.24, 6.8], [2.18, 11.2], [2.12, 12.8], [2.02, 17.3]], { n: 14, color: l => l === 1 || l === 3 ? TINT : C.CLOTH });
    kit.lathe([[1.95, 17.2], [2.85, 17.35], [2.85, 17.7], [1.9, 17.75]], { n: 14, capStart: true, capEnd: true, color: C.IRON });
    kit.ring(2.7, .08, .08, C.IRON, 14, PI / 2, 0, PI * 2, 18.5);
    for (let i = 0; i < 10; i++) { const a = i * PI / 5; kit.box(Math.cos(a) * 2.7, 18.1, Math.sin(a) * 2.7, .07, .75, .07, C.IRON) }
    kit.lathe([[1.75, 17.7], [1.75, 18.35], [1.6, 18.4]], { n: 10, capEnd: true, capColor: C.BRASS, color: C.IRON });
    for (let i = 0; i < 6; i++) { const a = i * PI / 3 + PI / 6; kit.box(Math.cos(a) * 1.62, 19.35, Math.sin(a) * 1.62, .13, 1.95, .13, C.BRASS) }
    kit.lathe([[1.7, 20.3], [2.75, 20.35], [2.6, 20.6], [1.7, 20.95], [.6, 21.15], [.2, 21.2]], { n: 14, capStart: true, color: l => l === 0 ? C.BRASS : TINT_DARK });
    kit.lathe([[.2, 21.15], [.12, 21.3], [0, 21.42]], { n: 6, color: C.BRASS });
    // Door, porch step and slit windows up the tower.
    kit.bevelBox(0, 3.0, -2.33, 1.1, 2.0, .2, .05, { top: C.BARK, side: C.BARK, bevel: C.BRASS, bottom: C.BARK, front: C.BARK_DARK });
    kit.prism([[-.6, 0], [-.45, .35], [0, .5], [.45, .35], [.6, 0]].map(([x, y]) => [x, y + 4.0]), .24, C.BRASS, C.BRASS, -2.3);
    kit.bevelBox(0, 2.1, -2.75, 1.6, .2, .8, .05, C.STONE_LIGHT);
    [[8.6, 0], [10.2, 2.1], [14.4, 4.2], [15.2, 1.1]].forEach(([y, a]) => kit.group({ rot: [0, a, 0] }, () => kit.box(0, y, -2.17, .35, .7, .1, C.INK)));
  });

  // Quarry hoist post (lone .7 x 5 x .7 host): braced post with a pulley, rope and
  // hook, and a winch drum. The fit box is the post; fittings reach out 0.8.
  world('Crane', { smooth: 30, fit: [[-.35, 0, -.35], [.35, 5, .35]], kind: 'tower' }, kit => {
    kit.bevelBox(0, 2.5, 0, .7, 5, .7, .06, { top: C.PLANK, side: C.BARK, bevel: C.PLANK, bottom: C.BARK });
    kit.bevelBox(0, 5.08, 0, .86, .16, .86, .04, C.IRON);
    for (const y of [.7, 2.5, 4.3]) kit.bevelBox(0, y, 0, .78, .14, .78, .03, C.IRON);
    for (let i = 0; i < 4; i++) kit.group({ rot: [0, i * PI / 2, 0] }, () => {
      kit.tube([[.62, .05, 0], [.33, 1.4, 0]], .07, { n: 5, color: C.BARK });
      kit.box(.62, .05, 0, .2, .1, .2, C.STONE);
    });
    // Pulley block on the front with rope and iron hook.
    kit.box(0, 4.65, -.4, .16, .5, .2, C.IRON);
    kit.group({ pos: [0, 4.45, -.46] }, () => { kit.group({ rot: [0, PI / 2, 0] }, () => kit.ring(.24, .1, .12, C.BRASS, 10)); kit.box(0, 0, 0, .2, .1, .1, C.IRON) });
    kit.tube([[0, 4.2, -.7], [0, 2.4, -.7]], .03, { n: 4, color: C.STRAW });
    kit.tube([[0, 2.42, -.7], [0, 2.1, -.7], [.06, 1.88, -.66], [.2, 1.9, -.7], [.22, 2.05, -.6]], .045, { n: 5, color: C.IRON });
    kit.blob(0, 2.48, -.7, .08, .1, .08, { sub: 0, color: C.IRON });
    // Winch drum and crank on the back.
    kit.group({ pos: [0, 1.6, .5], rot: [0, 0, PI / 2] }, () => kit.lathe([[.2, -.42], [.24, -.38], [.18, -.3], [.18, .3], [.24, .38], [.2, .42]], { n: 10, capStart: true, capEnd: true, color: l => l === 2 ? C.STRAW : C.PLANK }));
    kit.tube([[.44, 1.6, .5], [.56, 1.6, .5], [.56, 1.25, .54], [.7, 1.25, .54]], .035, { n: 4, color: C.IRON });
    for (const s of [-1, 1]) kit.box(s * .38, 1.6, .42, .06, .5, .3, C.IRON);
  });

  // Fishing pier / jetty deck (3 wide, stretched along Z). The fit box is the deck;
  // posts and rope coils stay within 0.2 of it so thick jetty hosts stay in slot.
  world('FishingPier', { smooth: 25, fit: [[-1.5, -.2, -4], [1.5, .2, 4]], kind: 'pier' }, kit => {
    for (let i = 0; i < 16; i++) {
      const z = -3.75 + i * .5, x = (hash(i, 501, 1) - .5) * .12;
      kit.box(x, .08 + (hash(i, 501, 2) - .5) * .03, z, 2.96, .2, .46, i % 4 === 1 ? C.BARK : hash(i, 501, 3) < .4 ? C.STRAW : C.PLANK);
    }
    for (const s of [-1, 1]) kit.box(s * 1.18, -.12, 0, .22, .26, 8, C.BARK_DARK);
    kit.box(0, -.12, 0, .2, .26, 7.6, C.BARK_DARK);
    for (const z of [-3.7, 0, 3.7]) for (const s of [-1, 1]) {
      kit.lathe([[.16, -.4], [.16, .3], [.12, .38]], { n: 6, capStart: true, capEnd: true, color: C.BARK, wobble: () => [s * 1.55, z] });
      kit.group({ pos: [s * 1.55, .18, z] }, () => kit.ring(.18, .05, .06, C.STRAW, 8, PI / 2));
    }
    for (const s of [-1, 1]) for (const [z0, z1] of [[-3.7, 0], [0, 3.7]]) kit.tube([[s * 1.55, .28, z0], [s * 1.58, .2, (z0 + z1) / 2], [s * 1.55, .28, z1]], .03, { n: 3, color: C.STRAW });
    kit.group({ pos: [.65, .19, 2.2] }, () => { kit.ring(.24, .1, .06, C.STRAW, 10, PI / 2); kit.ring(.12, .08, .06, C.STRAW, 8, PI / 2, 0, PI * 2, .04) });
    kit.group({ pos: [-.7, .2, -2.4], rot: [0, .5, 0] }, () => kit.lathe([[.15, 0], [.18, .14], [.17, .18]], { n: 8, capStart: true, capEnd: true, capColor: C.DEEP, color: C.PLANK }));
  });

  // Lookout spyglass (lone .5 x .5 x 3 host along Z): drawn brass tubes, leather
  // grip, sunshade and a glass objective at the front (-Z).
  world('Spyglass', { smooth: 40, kind: 'prop' }, kit => {
    kit.group({ rot: [PI / 2, 0, 0] }, () => {
      const prof = [[.22, -1.5], [.26, -1.46], [.26, -1.22], [.23, -1.18], [.23, -.42], [.25, -.38], [.25, -.28], [.2, -.24], [.2, .38], [.17, .42], [.17, .95], [.14, 1.0], [.14, 1.32], [.1, 1.38], [.11, 1.5]];
      kit.lathe(prof, { n: 12, capStart: true, capEnd: true, capColor: C.INK, color: l => l === 3 ? C.BARK : l === 1 || l === 5 || l === 9 || l === 11 ? C.BRASS : l === 7 ? C.GOLD : C.BRASS });
      kit.lathe([[0, -1.52], [.19, -1.49], [.2, -1.47]], { n: 12, color: C.GLASS });
    });
    for (const z of [-.8, .1]) kit.group({ pos: [0, 0, z] }, () => kit.ring(.235, .05, .06, C.IRON, 12));
  });

  // -------------------------------------------------------------------------
  // Agility course props. Spans (net, beam, ledge, chute, zip) are authored along
  // Z and stretch with the span length; perches are cylinder hosts.
  // -------------------------------------------------------------------------
  world('AgilityPerch', { smooth: 30, tint: 'C9B994', kind: 'agility' }, kit => {
    kit.lathe([[4.15, -.6], [4.5, -.3], [4.5, .42], [4.38, .6], [0, .6]], {
      n: 16, capStart: true, capColor: C.STONE_DARK,
      color: (l, i) => l === 0 ? C.STONE_DARK : l === 1 ? (hash(i, 601, 1) < .3 ? C.STONE_DARK : i % 2 ? C.STONE : C.STONE_LIGHT) : l === 2 ? C.STONE_LIGHT : (i % 2 ? TINT : TINT_LIGHT),
    });
    kit.ring(3.4, .22, .05, C.BRASS, 16, PI / 2, 0, PI * 2, .6);
    kit.ring(4.53, .16, .1, C.STRAW, 16, PI / 2, 0, PI * 2, .02);
    for (let i = 0; i < 4; i++) kit.group({ pos: [0, .61, 0], rot: [PI / 2, i * PI / 2, 0] }, () => kit.prism([[0, -.55], [.32, -.2], [0, -2.9], [-.32, -.2]], .03, i === 0 ? C.CRIMSON : TINT_DARK));
    kit.group({ pos: [0, .61, 0], rot: [PI / 2, 0, 0] }, () => kit.prism([[0, .5], [.5, 0], [0, -.5], [-.5, 0]], .04, C.BRASS));
    for (let i = 0; i < 8; i++) kit.group({ rot: [0, i * PI / 4 + PI / 8, 0] }, () => kit.box(0, .05, -4.53, .3, .5, .1, C.IRON));
  });
  world('ClimbNet', { smooth: 20, tint: '7A5636', kind: 'agility' }, kit => {
    for (const x of [-1.4, 1.4]) kit.tube([[x, 0, -6], [x, 0, 6]], .1, { n: 5, color: C.STRAW });
    for (const x of [-.7, 0, .7]) kit.tube([[x, 0, -6], [x, 0, 6]], .055, { n: 4, color: C.STRAW });
    for (let k = 0; k < 12; k++) {
      const z = -5.5 + k;
      kit.tube([[-1.4, 0, z], [1.4, 0, z]], .055, { n: 4, color: k % 2 ? C.CLOTH : C.STRAW });
      for (const x of [-1.4, -.7, 0, .7, 1.4]) kit.jewel(x, 0, z, .1, .09, .1, x === -1.4 || x === 1.4 ? TINT_LIGHT : C.STRAW);
    }
    for (const z of [-6.05, 6.05]) kit.tube([[-1.6, 0, z], [1.6, 0, z]], .15, { n: 6, color: TINT });
  });
  world('BalanceBeam', { smooth: 40, tint: '7A5636', kind: 'agility' }, kit => {
    kit.group({ rot: [PI / 2, 0, 0] }, () => {
      kit.lathe([[.42, -6], [.45, -5.6], [.43, -3.8], [.46, -2.1], [.44, 0], [.45, 2.2], [.43, 3.9], [.46, 5.6], [.42, 6]], {
        n: 10, sz: .61, capStart: true, capEnd: true, capColor: C.STRAW, color: (l, i) => hash(l, i, 611) < .3 ? TINT_DARK : i === 7 || i === 8 ? TINT_LIGHT : TINT,
      });
      for (const y of [-5.2, 0, 5.2]) kit.group({ pos: [0, y, 0] }, () => kit.lathe([[.47, -.12], [.47, .12]], { n: 10, sz: .64, capStart: true, capEnd: true, color: y === 0 ? C.BRASS : C.STRAW }));
      for (const [y0, y1] of [[-6.03, -5.99], [5.99, 6.03]]) kit.lathe([[.24, y0], [.24, y1]], { n: 10, sz: .61, capStart: true, capEnd: true, color: C.BARK_DARK });
    });
    kit.box(0, .275, 0, .36, .04, 10.2, C.PLANK);
  });
  world('RopeSwing', { smooth: 35, tint: '7A5636', fit: [[-.15, 0, -.15], [.15, 9.2, .15]], along: 'Y', kind: 'agility' }, kit => {
    for (let s = 0; s < 2; s++) {
      const pts = [];
      for (let k = 0; k <= 22; k++) { const y = .45 + k * (8.55 / 22), a = s * PI + k * .9; pts.push([Math.cos(a) * .045, y, Math.sin(a) * .045]) }
      kit.tube(pts, .065, { n: 4, color: s ? C.STRAW : C.CLOTH });
    }
    for (const y of [1.2, 2.5, 3.8]) kit.blob(0, y, 0, .14, .12, .14, { sub: 0, color: C.STRAW });
    // Top shackle on the cable and a wooden grip bar at the foot.
    kit.lathe([[.13, 8.85], [.15, 9.0], [.12, 9.05]], { n: 8, capStart: true, capEnd: true, color: C.IRON });
    kit.group({ pos: [0, 9.12, 0], rot: [0, PI / 2, 0] }, () => kit.ring(.09, .04, .04, C.IRON, 8));
    kit.tube([[-.4, .3, 0], [.4, .3, 0]], .07, { n: 6, color: TINT, capColor: TINT_LIGHT });
    for (const s of [-1, 1]) kit.tube([[0, .5, 0], [s * .26, .34, 0]], .035, { n: 4, color: C.STRAW });
    for (const s of [-1, 1]) kit.blob(s * .44, .3, 0, .09, .09, .09, { sub: 0, color: C.BRASS });
    kit.blob(0, .52, 0, .1, .09, .1, { sub: 0, color: C.STRAW });
  });
  world('LedgeWalk', { smooth: 0, tint: '7E817C', fit: [[-.65, -.25, -6], [.65, .25, 6]], kind: 'agility' }, kit => {
    const ledgeRock = seed => (n, m, i) => n[1] > .6 ? (hash(i, seed, 4) < .25 ? C.MOSS : hash(i, seed, 5) < .5 ? TINT_LIGHT : TINT) : n[1] < -.3 ? C.STONE_DARK : (hash(i, seed, 6) < .4 ? TINT_DARK : TINT);
    for (let k = 0; k < 9; k++) {
      const z = -5.35 + k * 1.34, x = (hash(k, 621, 1) - .5) * .18;
      kit.blob(x, .02, z, .62, .23, .74, { sub: 1, amount: .1, seed: 622 + k, squash: .9, color: ledgeRock(622 + k) });
    }
    for (let k = 0; k < 4; k++) kit.blob((hash(k, 623, 1) - .5) * .2, -.42, -4.5 + k * 3, .45, .3, .9, { sub: 0, amount: .2, seed: 630 + k, color: ledgeRock(630 + k) });
  });
  world('ZipLine', { smooth: 30, tint: '2E3B4E', fit: [[-.09, -.09, -8], [.09, .09, 8]], kind: 'agility' }, kit => {
    for (let s = 0; s < 2; s++) {
      const pts = [];
      for (let k = 0; k <= 32; k++) { const z = -7.6 + k * (15.2 / 32), a = s * PI + k * 1.2; pts.push([Math.cos(a) * .035, Math.sin(a) * .035, z]) }
      kit.tube(pts, .05, { n: 4, color: s ? TINT : C.IRON });
    }
    for (const z of [-7.8, 0, 7.8]) kit.group({ pos: [0, 0, z], rot: [PI / 2, 0, 0] }, () => kit.lathe([[.08, -.2], [.1, -.15], [.1, .15], [.08, .2]], { n: 8, capStart: true, capEnd: true, color: z === 0 ? C.IRON : C.BRASS }));
    for (let k = 0; k < 6; k++) kit.group({ pos: [0, -.05, -5.5 + k * 2.2], rot: [0, PI / 2, 0] }, () => kit.prism([[-.2, 0], [.2, 0], [0, -.4]], .02, [C.CRIMSON, C.GOLD, C.CLOTH][k % 3]));
  });
  world('SlideChute', { smooth: 25, tint: '7A5636', fit: [[-1.3, -.2, -6], [1.3, .2, 6]], kind: 'agility' }, kit => {
    kit.bevelBox(0, -.04, 0, 2.2, .32, 12, .06, { top: TINT_LIGHT, side: TINT, bevel: TINT, bottom: TINT_DARK });
    for (const x of [-.5, .5]) kit.box(x, .13, 0, .42, .03, 11.8, C.STRAW);
    for (const s of [-1, 1]) {
      kit.group({ pos: [s * 1.12, .18, 0], rot: [0, 0, -s * .22] }, () => kit.bevelBox(0, 0, 0, .24, .62, 12, .05, { top: C.BRASS, side: TINT, bevel: C.BRASS, bottom: TINT_DARK }));
    }
    for (let k = 0; k < 8; k++) kit.box(0, -.26, -5.25 + k * 1.5, 2.7, .14, .3, C.BARK_DARK);
    for (const z of [-5.9, 5.9]) kit.box(0, .1, z, 2.3, .06, .12, C.BRASS);
  });

  // -------------------------------------------------------------------------
  // Hunter props: snare stake, bird perch and the hovering swarm bloom.
  // -------------------------------------------------------------------------
  world('SnareTrap', { smooth: 30, tint: '8A6240', fit: [[-.125, 0, -.125], [.125, 1.2, .125]], kind: 'trap' }, kit => {
    kit.lathe([[.11, 0], [.12, .15], [.1, .98], [.12, 1.04], [.06, 1.2]], { n: 6, capStart: true, color: (l, i) => l === 2 ? C.BARK : i % 2 ? TINT : TINT_DARK });
    kit.box(.12, .86, 0, .3, .06, .06, C.BARK);
    kit.tube([[.12, .96, 0], [.3, .62, .04], [.42, .3, .05], [.46, .1, .02]], .02, { n: 4, color: C.STRAW });
    kit.group({ pos: [.46, 0, 0] }, () => kit.ring(.2, .04, .03, C.STRAW, 14, PI / 2, 0, PI * 2, .06));
    for (const a of [.3, 2.2, 4.1]) kit.group({ pos: [.46 + Math.cos(a) * .2, 0, Math.sin(a) * .2], rot: [0, a, -.3] }, () => kit.lathe([[.025, 0], [.03, .12], [0, .16]], { n: 4, capStart: true, color: C.PLANK }));
    for (let i = 0; i < 7; i++) {
      const a = i * .9 + .4, r = .16 + hash(i, 701, 1) * .1;
      kit.group({ pos: [Math.cos(a) * r, 0, Math.sin(a) * r], rot: [(hash(i, 701, 2) - .5) * .6, a, (hash(i, 701, 3) - .5) * .6] }, () => kit.jewel(0, .16, 0, .03, .18, .06, i % 2 ? C.LEAF : C.LEAF_DARK));
    }
    for (let i = 0; i < 3; i++) kit.blob(.46 + (i - 1) * .06, .05, (i % 2) * .05, .035, .035, .035, { sub: 0, color: C.ROSE });
  });
  world('BirdPerch', { smooth: 35, tint: '8A6240', fit: [[-.15, 0, -.15], [.15, 3, .15]], kind: 'trap' }, kit => {
    kit.lathe([[.15, 0], [.14, .3], [.12, 2.5], [.14, 2.56], [.14, 2.7], [.12, 2.76], [.12, 2.95]], { n: 8, capStart: true, color: (l, i) => l === 3 ? C.BRASS : l === 1 && i % 2 ? TINT_DARK : TINT });
    for (let i = 0; i < 3; i++) { const a = i * 2 * PI / 3 + .3; kit.tube([[Math.cos(a) * .48, 0, Math.sin(a) * .48], [Math.cos(a) * .12, .55, Math.sin(a) * .12]], .045, { n: 4, color: C.BARK }) }
    kit.lathe([[.05, 2.92], [.36, 3.0], [.4, 3.1], [.34, 3.08], [0, 3.03]], { n: 12, color: l => l === 1 ? C.BRASS : C.PLANK });
    for (let i = 0; i < 6; i++) { const a = i * 1.1; kit.jewel(Math.cos(a) * .18, 3.07, Math.sin(a) * .18, .04, .03, .04, C.STRAW) }
    // A small carved bird on the dish rim.
    kit.group({ pos: [.22, 3.1, -.05], rot: [0, .5, 0] }, () => {
      kit.blob(0, .12, 0, .1, .09, .13, { sub: 1, color: n => n[1] > .3 ? TINT_LIGHT : C.CLOTH });
      kit.blob(0, .24, -.1, .065, .065, .065, { sub: 0, color: TINT_LIGHT });
      kit.jewel(0, .24, -.18, .02, .02, .05, C.GOLD);
      kit.prism([[-.05, 0], [.05, 0], [0, .05]].map(([x, y]) => [x, y + .1]), .14, TINT_DARK, TINT_DARK, .17);
    });
    kit.group({ pos: [0, 2.42, -.13] }, () => kit.prism([[-.06, 0], [.06, 0], [.07, -.5], [0, -.42], [-.07, -.5]], .02, C.CRIMSON));
  });
  world('SwarmBloom', { smooth: 35, tint: 'F2C14E', fit: [[-.75, 1.05, -.75], [.75, 2.55, .75]], kind: 'trap' }, kit => {
    kit.tube([[0, 0, 0], [.1, .6, .05], [-.05, 1.2, 0], [0, 1.55, 0]], [.06, .05, .045, .04], { n: 5, color: C.LEAF });
    for (const [y, a] of [[.35, 0], [.75, 2.3], [1.1, 4.4]]) kit.group({ pos: [0, y, 0], rot: [0, a, .9] }, () => kit.jewel(0, .22, 0, .05, .26, .1, a ? C.LEAF_DARK : C.LEAF));
    kit.group({ pos: [0, 1.6, 0], rot: [.25, .4, 0] }, () => {
      for (let p = 0; p < 7; p++) kit.group({ rot: [0, p * 2 * PI / 7, 1.05] }, () => kit.jewel(0, .3, 0, .15, .32, .05, p % 2 ? TINT : TINT_LIGHT));
      for (let p = 0; p < 5; p++) kit.group({ rot: [0, p * 2 * PI / 5 + .3, .55] }, () => kit.jewel(0, .22, 0, .1, .22, .04, TINT_DARK));
      kit.blob(0, .06, 0, .1, .07, .1, { sub: 0, color: C.FLAME });
    });
    // Little winged critters circling the bloom.
    for (let i = 0; i < 6; i++) {
      const a = i * 2 * PI / 6 + .3, r = .5 + hash(i, 711, 1) * .15, y = 1.25 + hash(i, 711, 2) * 1.15;
      kit.group({ pos: [Math.cos(a) * r, y, Math.sin(a) * r], rot: [(hash(i, 711, 3) - .5) * .5, -a, 0] }, () => {
        kit.jewel(0, 0, 0, .035, .035, .1, C.INK);
        for (const s of [-1, 1]) kit.group({ rot: [0, 0, s * .45] }, () => kit.jewel(s * .09, 0, 0, .08, .015, .055, i % 2 ? C.GLASS : TINT_LIGHT));
      });
    }
    for (let i = 0; i < 8; i++) { const a = i * 1.7, r = .3 + hash(i, 712, 1) * .4; kit.jewel(Math.cos(a) * r, 1.4 + hash(i, 712, 2) * 1.0, Math.sin(a) * r, .03, .03, .03, i % 2 ? C.GLINT : C.FLAME) }
  });

  // -------------------------------------------------------------------------
  // Dedicated shapes that replace generic aliases.
  // -------------------------------------------------------------------------
  // Warden Reach waystone (2.5 x 6 x 2.5): rune-cut monolith with a brass collar
  // and a cradle for the world's floating signal prism above it.
  world('Waystone', { smooth: 0, tint: 'C15557', fit: [[-1.25, 0, -1.25], [1.25, 6, 1.25]], kind: 'statue' }, kit => {
    for (let i = 0; i < 7; i++) { const a = i * 2 * PI / 7 + .2; kit.blob(Math.cos(a) * 1.25, .16, Math.sin(a) * 1.25, .3, .22, .28, { sub: 0, amount: .2, seed: 801 + i, color: rock(801 + i) }) }
    kit.lathe([[1.22, 0], [1.12, 1.0], [1.0, 4.6], [.86, 5.35], [.5, 5.8], [.42, 5.95]], {
      n: 4, phase: PI / 4, capStart: true, capEnd: true, capColor: C.STONE_LIGHT, jitter: jitterOf(802, .04),
      color: (l, i) => l === 0 ? (i % 2 ? C.MOSS : C.STONE) : l >= 3 ? C.STONE_LIGHT : (i % 2 ? C.STONE : C.STONE_LIGHT),
    });
    kit.lathe([[.9, 5.05], [.95, 5.12], [.95, 5.32], [.88, 5.38]], { n: 4, phase: PI / 4, capStart: true, capEnd: true, color: C.BRASS });
    // Rune channels on all four faces.
    for (let f = 0; f < 4; f++) kit.group({ rot: [0, f * PI / 2, 0] }, () => {
      const depth = y => -(1.12 - (y - 1) * (.12 / 3.6)) * .707 - .05;
      kit.box(0, 2.9, depth(2.9), .1, 2.6, .05, TINT);
      for (const [y, w, x] of [[1.9, .5, .15], [2.6, .42, -.13], [3.3, .55, .16], [3.9, .36, -.1]]) kit.box(x, y, depth(y), w, .09, .05, TINT_LIGHT);
      kit.jewel(0, 4.45, depth(4.45) - .02, .16, .2, .05, TINT_LIGHT);
    });
    for (let i = 0; i < 4; i++) { const a = i * PI / 2 + PI / 4; kit.tube([[Math.cos(a) * .4, 5.85, Math.sin(a) * .4], [Math.cos(a) * .55, 6.2, Math.sin(a) * .55], [Math.cos(a) * .4, 6.55, Math.sin(a) * .4]], [.07, .06, .04], { n: 5, color: C.BRASS }) }
  });
  // Tempest storm pylon (1.2 x 7 shaft): finned iron mast wound with glowing coils
  // and a claw crown under the world's Neon crystal.
  world('StormPylon', { smooth: 30, tint: 'BFD7FF', fit: [[-.6, 0, -.6], [.6, 7, .6]], kind: 'tower' }, kit => {
    kit.lathe([[.6, 0], [.56, .35], [.44, .6], [.4, 6.3], [.52, 6.55], [.58, 7.0]], { n: 6, capStart: true, capEnd: true, capColor: C.INK, color: l => l === 3 || l === 0 ? C.BRASS : C.IRON });
    for (let k = 0; k < 5; k++) kit.ring(.5, .14, .16, k % 2 ? TINT : TINT_LIGHT, 10, PI / 2, 0, PI * 2, 1.4 + k * 1.05);
    for (let f = 0; f < 3; f++) kit.group({ rot: [0, f * 2 * PI / 3 + PI / 6, 0] }, () => kit.group({ rot: [0, PI / 2, 0] }, () => kit.prism([[.36, .7], [.95, 1.3], [1.05, 4.6], [.7, 5.9], [.36, 5.9]], .08, C.IRON, C.BRASS)));
    for (let f = 0; f < 3; f++) { const a = f * 2 * PI / 3 + PI / 6; kit.tube([[Math.cos(a) * .45, 6.9, Math.sin(a) * .45], [Math.cos(a) * .75, 7.3, Math.sin(a) * .75], [Math.cos(a) * .5, 7.85, Math.sin(a) * .5]], [.1, .08, .04], { n: 5, color: C.BRASS }) }
    kit.jewel(0, 7.25, 0, .18, .28, .18, TINT_LIGHT);
  });
  // Tempest storm spire: five jagged, twisting stone tiers with crystal veins.
  // The spire's model box is about 18.6 x 77 x 16.2.
  world('StormSpire', { smooth: 0, tint: 'BFD7FF', kind: 'tower' }, kit => {
    const tiers = [[6.9, 0, 18.4, 0], [5.6, 16.6, 18.2, .5], [4.2, 33.8, 16.6, 1.1], [3.1, 49.6, 15.1, 1.6], [2.0, 63.8, 13.4, 2.2]];
    tiers.forEach(([r, y, h, twist], t) => kit.group({ pos: [t % 2 ? .4 : -.3, 0, 0], rot: [0, twist, (t % 2 ? -1 : 1) * .03] }, () => kit.lathe([[r * .95, y], [r * 1.06, y + h * .3], [r * .92, y + h * .78], [r * .62, y + h]], {
      n: 6, capStart: true, capEnd: true, jitter: jitterOf(901 + t, .14), lift: (l, i) => l === 3 ? (hash(i, 902 + t, 1) - .5) * 1.6 : 0,
      color: (l, i) => l === 4 ? (hash(i, t, 903) < .4 ? TINT_LIGHT : C.STONE_LIGHT) : hash(l, i + t * 9, 904) < .25 ? C.INK : (i + l) % 2 ? C.STONE : C.STONE_LIGHT, capColor: undefined,
    })));
    tiers.forEach(([r, y, h], t) => {
      for (let k = 0; k < 3; k++) {
        const a = k * 2.1 + t * 1.3, rr = r * .85;
        kit.group({ pos: [Math.cos(a) * rr, y + h * (.35 + .2 * k), Math.sin(a) * rr], rot: [0, -a, 0] }, () => crystal(kit, 0, 0, 0, 0, -1.0, 2.4 + r * .3, .35 + r * .05, 910 + t * 3 + k));
      }
    });
    for (let i = 0; i < 5; i++) { const a = i * 1.26; kit.jewel(Math.cos(a) * 4.5, 66 + i * 2.2, Math.sin(a) * 4.5, .3, .7, .3, i % 2 ? TINT : TINT_LIGHT) }
  });
  // Gloomhollow stalactite (1.8 x 7, hanging): drip cone with a glowing tip and
  // two smaller cones, rooted in the cavern roof at the top.
  world('Stalactite', { smooth: 35, tint: 'B59CFF', kind: 'rock' }, kit => {
    const drip = (x, z, top, len, r, seed) => kit.group({ pos: [x, 0, z] }, () => kit.lathe([[0, top - len], [r * .22, top - len * .9], [r * .45, top - len * .72], [r * .7, top - len * .45], [r * .9, top - len * .18], [r, top]], {
      n: 7, capEnd: true, capColor: C.STONE_DARK, jitter: (l, i) => l === 0 ? 1 : 1 + (hash(l, i, seed) - .5) * .25,
      color: (l, i) => l === 0 ? TINT_LIGHT : l === 1 ? TINT : l === 2 && i % 2 ? TINT_DARK : hash(l, i, seed + 1) < .4 ? C.STONE_DARK : i % 3 ? C.SLATE : C.STONE,
    }));
    drip(0, 0, 7, 7, .9, 951);
    drip(.55, .3, 7, 3.2, .38, 952);
    drip(-.5, -.35, 7, 4.1, .42, 953);
    drip(.1, -.6, 7, 2.2, .3, 954);
    kit.blob(0, 6.75, 0, .95, .3, .95, { sub: 1, amount: .15, seed: 955, color: rock(955, false) });
  });
  // Ruined column (2.2 wide, 4-9 tall): fluted drum on a plinth with a broken,
  // jagged top, rubble and creeping ivy.
  world('RuinColumn', { smooth: 30, kind: 'statue' }, kit => {
    kit.bevelBox(0, .25, 0, 2.2, .5, 2.2, .08, { top: C.STONE_LIGHT, side: C.STONE, bevel: C.STONE_LIGHT, bottom: C.STONE_DARK });
    kit.lathe([[.98, .5], [1.0, .62], [.92, .76], [.8, .84]], { n: 14, capStart: true, color: C.MARBLE });
    kit.lathe([[.8, .8], [.78, 2.4], [.75, 4.2], [.74, 5.3]], {
      n: 16, capEnd: true, capColor: C.STONE_LIGHT, jitter: (l, i) => i % 2 ? .9 : 1,
      lift: (l, i) => l === 3 ? -hash(i, 961, 1) * .9 - (Math.abs(i - 5) < 3 ? .8 : 0) : 0,
      color: (l, i) => l === 0 && hash(i, 962, 1) < .2 ? C.MOSS : l === 2 && hash(i, 962, 2) < .3 ? C.STONE : C.MARBLE,
    });
    kit.blob(.95, .62, -.8, .25, .16, .22, { sub: 0, amount: .2, seed: 963, color: C.MARBLE });
    kit.blob(-.82, .6, .9, .2, .12, .18, { sub: 0, amount: .2, seed: 964, color: C.STONE_LIGHT });
    const ivy = [];
    for (let k = 0; k <= 10; k++) { const a = k * .7 + 1, y = .6 + k * .38; ivy.push([Math.cos(a) * .8, y, Math.sin(a) * .8]) }
    kit.tube(ivy, .05, { n: 4, color: C.LEAF_DARK });
    ivy.forEach(([x, y, z], k) => { if (k % 2) kit.jewel(x * 1.06, y, z * 1.06, .12, .1, .12, k % 4 === 1 ? C.MOSS : C.LEAF) });
  });
  // Guild Hall column (1.6 x 16): Attic base, fluted shaft with entasis, brass
  // bands and an echinus that meets the hall's own capital block.
  world('Column', { smooth: 30, kind: 'statue' }, kit => {
    kit.bevelBox(0, .25, 0, 1.6, .5, 1.6, .06, C.MARBLE);
    kit.lathe([[.74, .5], [.76, .62], [.68, .74], [.7, .84], [.62, .9]], { n: 14, capStart: true, color: l => l === 1 ? C.BRASS : C.MARBLE });
    kit.lathe([[.6, .9], [.62, 4.5], [.6, 9], [.55, 14.6], [.56, 15.0]], { n: 16, jitter: (l, i) => i % 2 ? .9 : 1, color: (l, i) => l === 3 ? C.MARBLE : i % 2 ? C.MARBLE : C.CLOTH });
    kit.lathe([[.56, 15.0], [.64, 15.2], [.76, 15.55], [.8, 15.8], [.8, 16]], { n: 14, capEnd: true, capColor: C.MARBLE, color: l => l === 0 ? C.BRASS : C.CLOTH });
    for (const y of [4.6, 11.2]) kit.ring(.62, .1, .16, C.BRASS, 14, PI / 2, 0, PI * 2, y);
  });
  // Cave torch (.5 x 3.6 post): stone-footed post, cloth wraps, iron fire bowl
  // with tinted coals beneath the world's Neon flame.
  world('Torch', { smooth: 35, tint: 'B59CFF', fit: [[-.25, 0, -.25], [.25, 3.6, .25]], kind: 'lamp' }, kit => {
    for (let i = 0; i < 5; i++) { const a = i * 2 * PI / 5; kit.blob(Math.cos(a) * .36, .08, Math.sin(a) * .36, .17, .12, .15, { sub: 0, amount: .2, seed: 971 + i, color: rock(971 + i, false) }) }
    kit.lathe([[.22, 0], [.2, .25], [.16, 2.5], [.18, 2.62], [.17, 3.02]], { n: 7, capStart: true, color: (l, i) => l === 2 ? C.IRON : hash(l, i, 972) < .3 ? C.BARK_DARK : C.BARK });
    for (let k = 0; k < 3; k++) kit.lathe([[.18 - k * .008, .9 + k * .45], [.19 - k * .008, 1.12 + k * .45]], { n: 7, capStart: true, capEnd: true, color: C.CLOTH, phase: k });
    kit.lathe([[.1, 2.98], [.3, 3.2], [.36, 3.5], [.33, 3.56], [.26, 3.3], [0, 3.2]], { n: 10, color: l => l === 2 ? C.BRASS : C.IRON });
    for (let i = 0; i < 5; i++) { const a = i * 1.3; kit.jewel(Math.cos(a) * .14, 3.33, Math.sin(a) * .14, .09, .07, .09, i % 2 ? TINT_LIGHT : TINT) }
    for (let i = 0; i < 4; i++) { const a = i * PI / 2 + .4; kit.tube([[Math.cos(a) * .32, 3.48, Math.sin(a) * .32], [Math.cos(a) * .4, 3.62, Math.sin(a) * .4], [Math.cos(a) * .33, 3.78, Math.sin(a) * .33]], .03, { n: 4, color: C.IRON }) }
  });
  // Herb bed (round 4.6 x 1.6 slot): stone-ringed raised bed of soil with tinted
  // herb sprigs and small blossoms. Crop patches use their resource's crop shape.
  world('CropBed', { smooth: 40, tint: '9DF3D7', kind: 'crop' }, kit => {
    for (let i = 0; i < 11; i++) { const a = i * 2 * PI / 11; kit.blob(Math.cos(a) * 2.02, .26, Math.sin(a) * 2.02, .34, .28, .3, { sub: 0, amount: .15, seed: 981 + i, color: rock(981 + i) }) }
    kit.lathe([[1.95, .05], [1.92, .48], [1.55, .6], [.8, .66], [0, .68]], { n: 12, color: (l, i) => l >= 2 && hash(i, 982, l) < .3 ? C.BARK_DARK : C.SOIL });
    const clumps = [[0, 0, 1.0], [1.05, .3, .8], [-.95, .5, .85], [.3, -1.0, .75], [-.55, -.8, .7], [.55, 1.0, .7], [-.2, 1.2, .6]];
    clumps.forEach(([x, z, s], c) => {
      for (let k = 0; k < 5; k++) kit.group({ pos: [x, .62, z], rot: [0, k * 2 * PI / 5 + c, .45 + hash(k, c, 983) * .3] }, () => kit.jewel(0, .42 * s, 0, .09 * s, .44 * s, .05 * s, k % 3 === 0 ? TINT_LIGHT : k % 3 === 1 ? TINT : TINT_DARK));
      kit.jewel(x, .62 + .78 * s, z, .07, .07, .07, c % 2 ? C.GLINT : C.LAVENDER);
    });
  });
  // Shrub (2.6 cube slot, sunk 0.4 into the ground): clustered leafy mounds with
  // a few berries. Tint = foliage.
  world('Bush', { smooth: 45, tint: '6C9A58', kind: 'plant' }, kit => {
    kit.blob(0, 1.15, 0, 1.25, 1.0, 1.2, { sub: 1, amount: .14, seed: 991, squash: .6, color: foliage(991) });
    kit.blob(.6, 1.5, .35, .75, .7, .7, { sub: 1, amount: .16, seed: 992, squash: .7, color: foliage(992) });
    kit.blob(-.55, 1.55, -.3, .7, .75, .7, { sub: 1, amount: .16, seed: 993, squash: .7, color: foliage(993) });
    kit.blob(.05, 2.0, -.05, .55, .6, .55, { sub: 1, amount: .18, seed: 994, color: foliage(994) });
    for (let i = 0; i < 9; i++) { const a = i * 2.4, r = .9 + hash(i, 995, 1) * .3, y = 1.0 + hash(i, 995, 2) * 1.1; kit.jewel(Math.cos(a) * r, y, Math.sin(a) * r, .09, .09, .09, i % 3 ? C.ROSE : C.GLINT) }
    for (let i = 0; i < 4; i++) { const a = i * PI / 2 + .5; kit.tube([[Math.cos(a) * .2, 0, Math.sin(a) * .2], [Math.cos(a) * .7, .55, Math.sin(a) * .7]], [.07, .04], { n: 4, color: C.BARK }) }
  });
  // Layered outcrop (owns its three-rock model, about 8.5 x 4.6 x 9.2): stepped
  // strata ledges with mossy tops and loose scree.
  world('RockOutcrop', { smooth: 0, kind: 'rock' }, kit => {
    const ledge = (x, z, r, y0, h, yaw, seed, layers) => kit.group({ pos: [x, 0, z], rot: [0, yaw, 0] }, () => {
      for (let k = 0; k < layers; k++) {
        const rr = r * (1 - k * .2), yb = y0 + k * h, top = yb + h;
        kit.lathe([[rr * 1.02, yb], [rr * 1.06, yb + h * .45], [rr, top]], {
          n: 7, sx: 1.25, capStart: k === 0, capEnd: true, jitter: jitterOf(seed + k, .16), lift: (l, i) => l === 2 ? (hash(i, seed + k, 7) - .5) * h * .4 : 0,
          color: (l, i) => l === 3 ? (hash(i, seed + k, 8) < .55 ? C.MOSS : C.STONE_LIGHT) : hash(l, i + k * 7, seed) < .3 ? C.STONE_DARK : l === 1 ? C.STONE_LIGHT : C.STONE,
          capColor: C.STONE_DARK,
        });
      }
    });
    ledge(-.4, -.6, 2.6, -.3, 1.35, .2, 1001, 3);
    ledge(2.4, 1.6, 1.7, -.2, 1.1, 1.3, 1011, 2);
    ledge(-2.4, 2.1, 1.3, -.2, .85, 2.1, 1021, 2);
    for (let i = 0; i < 7; i++) { const a = i * .9 + .3, r = 3.2 + hash(i, 1031, 1) * .9; kit.blob(Math.cos(a) * r, .12, Math.sin(a) * r * 1.05, .32, .2, .28, { sub: 0, amount: .25, seed: 1032 + i, color: rock(1032 + i) }) }
  });
  // Palm (tilted trunk host owning its frond disk): ringed, curving trunk with
  // drooping fronds and coconuts. Uniform fit.
  world('PalmTree', { smooth: 40, tint: '6FA05A', kind: 'tree' }, kit => {
    const trunk = [];
    for (let k = 0; k <= 9; k++) { const t = k / 9; trunk.push([1.3 * t * t, t * 6.4, .1 * Math.sin(t * PI)]) }
    kit.tube(trunk, i => .42 - i * .025, { n: 7, color: (i, k) => i % 2 ? C.BARK : C.PLANK, jitter: (i, k) => i % 2 ? 1.08 : .96 });
    roots(kit, 4, .45, .5, 1041, C.BARK, .2);
    const top = [1.3, 6.4, .1];
    for (let f = 0; f < 8; f++) {
      const a = f * 2 * PI / 8 + .2, droop = .8 + hash(f, 1042, 1) * .6, len = 3.3 + hash(f, 1042, 2) * .5;
      kit.group({ pos: top, rot: [0, -a, 0] }, () => {
        for (let s = 0; s < 4; s++) {
          const t0 = s / 4, t1 = (s + 1) / 4, x0 = len * t0, x1 = len * t1;
          const y0 = .55 * Math.sin(t0 * PI * .9) - droop * t0 * t0 * 1.8, y1 = .55 * Math.sin(t1 * PI * .9) - droop * t1 * t1 * 1.8;
          const w0 = .55 * Math.sin(PI * (.15 + t0 * .8)), w1 = .55 * Math.sin(PI * (.15 + t1 * .8));
          kit.loft([{ z: 0, points: [[0, 0], [w0, .06], [0, -.04], [-w0, .06]] }, { z: 1, points: [[0, 0], [w1, .06], [0, -.04], [-w1, .06]] }].map((sec, q) => ({ z: q ? x1 : x0, points: sec.points.map(([px, py]) => [px, py + (q ? y1 : y0)]) })), { capStart: s === 0, capEnd: s === 3, color: (sec, e) => e < 2 ? (s % 2 ? TINT : TINT_LIGHT) : TINT_DARK });
        }
        kit.tube([[0, .05, 0], [0, .5, len * .5], [0, -.2, len * .95]].map(([px, py, pz]) => [px, py - droop * Math.pow(pz / len, 2) * 1.6, pz]), [.06, .04, .02], { n: 3, color: TINT_DARK });
      });
    }
    for (let c = 0; c < 3; c++) { const a = c * 2.1; kit.blob(top[0] + Math.cos(a) * .35, top[1] - .35, top[2] + Math.sin(a) * .35, .24, .26, .24, { sub: 0, color: C.BARK_DARK }) }
  });
  // Dead tree (trunk host owning one bare bough; a narrow, mostly planar box):
  // gnarled trunk with split crown, broken limbs and bracket fungus.
  world('DeadTree', { smooth: 35, tint: 'B8A68A', kind: 'tree' }, kit => {
    kit.tube([[0, -.1, 0], [.1, 2.0, 0], [-.15, 3.8, .05], [.05, 5.2, 0]], [.55, .45, .36, .26], { n: 7, capStart: true, color: barkBands(1051, C.BARK, C.BARK_DARK), jitter: jitterOf(1052, .1) });
    roots(kit, 4, .5, .6, 1053, C.BARK_DARK, .26);
    const limbs = [[[.05, 4.4, 0], [.9, 5.7, .25], [1.6, 7.0, .4], [1.85, 7.7, .35]], [[0, 4.9, 0], [-.55, 6.2, -.2], [-.95, 7.4, -.3]], [[.05, 5.2, 0], [.25, 6.6, .1], [.1, 7.6, 0]], [[-.1, 3.3, 0], [-.8, 3.9, .1], [-1.2, 4.8, .15]]];
    for (const limb of limbs) kit.tube(limb, i => .26 - i * .07, { n: 5, color: (i, k) => k % 3 ? C.BARK : C.BARK_DARK });
    for (const [p, q] of [[[1.25, 6.3, .3], [1.75, 6.5, -.2]], [[-.75, 6.8, -.25], [-1.2, 7.0, .2]], [[-1.0, 4.4, .1], [-1.35, 4.3, -.3]]]) kit.tube([p, q], [.08, .03], { n: 4, color: C.BARK_DARK });
    for (const [y, a] of [[1.6, .3], [2.4, 2.4], [3.1, 4.0]]) kit.group({ pos: [Math.cos(a) * .5, y, Math.sin(a) * .5], rot: [0, -a, 0] }, () => kit.lathe([[0, 0], [.32, .04], [.3, .1], [0, .12]], { n: 7, sz: .6, color: l => l === 0 ? TINT_DARK : TINT }));
  });
};
