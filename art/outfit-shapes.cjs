// NPC outfits (docs/DEPTH-CONTRACT.md §52): hats, hoods, helms, aprons, cloaks,
// mantles, satchels, belts and the trade props the townsfolk hold, forged on
// each client by npc.client.lua through the MeshForge outfit API and welded to
// the server's R15-style rig (the primitive hat / prop parts stay as the
// fallback and are hidden locally once the mesh exists).
// Loaded by art/generate-props.cjs; output goes to art/OutfitCatalog.lua
// (ReplicatedStorage.AetherOutfitArt, its own download) plus one OBJ each.
//
// Frames ("bone space", studs at rig scale 1, +Y up, the face looks down -Z):
//   head  - origin at the Head's centre (the head is a 1.2 stud cube);
//   torso - origin at the UpperTorso's centre (2 x 1.5 x 1; the LowerTorso
//           sits 1 stud below; the ground is 3.55 below);
//   hand  - origin at the grip (the RightHand's centre); a held prop's shaft
//           runs down local -Y like the server's fallback props.
// The client places each piece at its spec offset (shared/NpcStyle.lua).
//
// Every surface is a smooth-shaded lathe, loft, tube or subdivided ellipsoid
// (>= 10 segments around, crease 50-58 degrees): no boxes, prisms or facets.
// TINT faces take the NPC's dye (the cloth colour of their look, quantised to
// NpcStyle.DYES), TINT_DARK / TINT_LIGHT its shades; leather, brass, iron,
// straw, parchment and glass stay fixed.
'use strict';
module.exports = ({ outfit, C, PI }) => {
  const { TINT: T, TINT_DARK: TD, TINT_LIGHT: TL } = C;
  const CLOTH = 55, HARD = 50;
  const LEATHER = C.TIMBER, BRASS = C.BRASS, IRON = C.IRON, STRAW = C.STRAW, PAPER = C.CLOTH, WOOD = C.HANDLE, GLASS = C.GLASS;

  // Colour by ring band (level) for upright lathes and tubes.
  const bands = (...cols) => level => cols[Math.max(0, Math.min(cols.length - 1, level))];
  const byLevel = map => level => map[level] ?? map.default;
  // Torus (bands, brims, rims): n around, m around the tube.
  const torus = (kit, { pos = [0, 0, 0], rot = [0, 0, 0], R = 1, r = .05, n = 32, m = 10, sx = 1, sz = 1, color = T }) =>
    kit.group({ pos, rot }, () => kit.lathe(Array.from({ length: m + 1 }, (_, b) => { const a = b * 2 * PI / m; return [R + r * Math.cos(a), r * Math.sin(a)] }), { n, color, sx, sz }));
  // Lathe laid along -Z (a lens, a lamp facing forward).
  const forward = (kit, pos, profile, opts) => kit.group({ pos, rot: [-PI / 2, 0, 0] }, () => kit.lathe(profile, opts));
  // Smooth tapered tube along a polyline.
  const rod = (kit, pts, r, color, n = 12, tip = 1) => {
    const m = pts.length;
    kit.tube(pts, i => typeof r === 'function' ? r(i, m) : r * (1 - (1 - tip) * i / Math.max(1, m - 1)), { n, color });
  };
  // Lofted sheet (aprons, cloaks, tabards, panels): sections run down -Y from
  // `top` to `top - len`; each section is a thin lens `w(t)` wide, `th(t)`
  // thick, its depth `depth(t, x)` (z) so the sheet wraps the body / folds.
  const sheet = (kit, { top = 0, len = 1, w = () => 1, th = () => .05, depth = () => 0, steps = 8, m = 16, cols = [T], xoff = () => 0 }) =>
    kit.group({ pos: [0, top, 0], rot: [PI / 2, 0, 0] }, () => kit.loft(
      Array.from({ length: steps + 1 }, (_, s) => {
        const t = s / steps, half = Math.max(w(t) / 2, .02), tt = Math.max(th(t), .012);
        return { z: t * len, points: Array.from({ length: m }, (_, k) => {
          const a = k * 2 * PI / m, x = Math.cos(a) * half + xoff(t);
          // pitch +90 maps local (x, y, z) -> (x, -z, y): section y becomes depth z.
          return [x, depth(t, x) + Math.sin(a) * tt];
        }) };
      }), { color: s => cols[Math.max(0, Math.min(cols.length - 1, Math.floor(s * cols.length / (steps + 1))))] }));
  // Rounded box by lofted superellipse sections along local +Z.
  const roundBox = (kit, { pos = [0, 0, 0], rot = [0, 0, 0], len = 1, w = 1, h = 1, steps = 6, m = 16, ex = 2.8, shape = () => [1, 1], cols = [T] }) =>
    kit.group({ pos, rot }, () => kit.loft(
      Array.from({ length: steps + 1 }, (_, s) => {
        const t = s / steps, [sw, sh] = shape(t);
        return { z: t * len - len / 2, points: Array.from({ length: m }, (_, k) => {
          const a = k * 2 * PI / m, c = Math.cos(a), sn = Math.sin(a);
          return [Math.sign(c) * Math.abs(c) ** (2 / ex) * w * sw / 2, Math.sign(sn) * Math.abs(sn) ** (2 / ex) * h * sh / 2];
        }) };
      }), { color: s => cols[Math.max(0, Math.min(cols.length - 1, Math.floor(s * cols.length / (steps + 1))))] }));
  // Cambered blade with real thickness (feathers, sword and spear blades, visors).
  const blade = (kit, { pos = [0, 0, 0], rot = [0, 0, 0], len = 1, w = .3, th = .04, tip = .05, steps = 6, m = 12, belly = .3, camber = 0, cols = [T] }) =>
    kit.group({ pos, rot }, () => kit.group({ rot: [-PI / 2, 0, 0] }, () => kit.loft(
      Array.from({ length: steps + 1 }, (_, s) => {
        const t = s / steps;
        const prof = t < belly ? .55 + .45 * Math.sin(t / belly * PI / 2) : 1 - (1 - tip) * ((t - belly) / (1 - belly)) ** 1.2;
        const wt = Math.max(w * prof, .012), tt = Math.max(th * Math.sqrt(prof), .006), oy = camber * Math.sin(PI * t);
        return { z: t * len, points: Array.from({ length: m }, (_, k) => { const a = k * 2 * PI / m; return [Math.cos(a) * wt / 2, oy + Math.sin(a) * tt] }) };
      }), { color: s => cols[Math.max(0, Math.min(cols.length - 1, Math.floor(s * cols.length / (steps + 1))))] })));
  const dome = (kit, x, y, z, r, color, sub = 2) => kit.blob(x, y, z, r, r, r, { sub, color: () => color });

  // =========================================================================
  // Head pieces (origin = head centre; crown top at y 0.6, face at z -0.6).
  // =========================================================================
  // Wayfarer: a wide felt brim with a rolled edge, pinched crown, ribbon band.
  outfit('HatWayfarer', { smooth: CLOTH, tint: '4A3B2A', kind: 'outfit', slot: 'head' }, kit => {
    kit.lathe([[.6, .5], [1.0, .52], [1.22, .55], [1.3, .61], [1.24, .66], [1.0, .63], [.66, .63], [.63, .72], [.64, .98], [.56, 1.12],
      [.36, 1.18], [0, 1.2]], { n: 28, color: byLevel({ 6: TD, 7: TD, default: T }), capStart: true });
    torus(kit, { pos: [0, .74, 0], R: .645, r: .055, n: 28, color: C.CRIMSON });
    kit.blob(.5, .78, -.36, .06, .1, .04, { sub: 2, color: () => BRASS });
  });
  // Top hat: tall crown with a band and a curled brim.
  outfit('HatTop', { smooth: CLOTH, tint: '1A1A1A', kind: 'outfit', slot: 'head' }, kit => {
    kit.lathe([[.58, .5], [.88, .53], [1.0, .58], [.96, .64], [.82, .63], [.6, .63], [.57, .78], [.6, 1.38], [.63, 1.5], [.6, 1.56], [0, 1.58]],
      { n: 28, color: byLevel({ 6: TD, default: T }), capStart: true });
    torus(kit, { pos: [0, .78, 0], R: .585, r: .06, n: 28, color: C.GOLD });
  });
  // Flat cap: a soft crown over a cambered visor.
  outfit('HatCap', { smooth: CLOTH, tint: '6D4C41', kind: 'outfit', slot: 'head' }, kit => {
    kit.lathe([[.66, .38], [.7, .52], [.66, .68], [.52, .82], [.28, .9], [0, .93]], { n: 24, sz: 1.05, color: bands(TD, T, T, TL, TL), capStart: true });
    blade(kit, { pos: [0, .44, -.58], rot: [-1.42, 0, 0], len: .5, w: 1.08, th: .03, tip: .62, belly: .2, camber: .05, m: 12, cols: [TD] });
    dome(kit, 0, .93, 0, .07, TD, 1);
  });
  // Tinker's goggles: a strap band and two domed glass lenses in brass rims.
  outfit('HatGoggles', { smooth: HARD, tint: '2B2B2B', kind: 'outfit', slot: 'head' }, kit => {
    // QC M3: a padded strap that follows the square head (a superellipse loop, not
    // a ring that the head's corners poke through), a stitched brow band, two
    // deep brass cups with a bevelled rim and domed lenses, a nose bridge, side
    // rivets and a buckle at the back. (The strap colour is the dye: TD stitching.)
    const loop = (half, y, ex, n) => Array.from({ length: n + 1 }, (_, i) => {
      const a = i * 2 * PI / n, c = Math.cos(a), sn = Math.sin(a);
      return [Math.sign(c) * Math.abs(c) ** (2 / ex) * half, y, Math.sign(sn) * Math.abs(sn) ** (2 / ex) * half];
    });
    kit.tube(loop(.66, .33, 7, 24), .075, { n: 12, color: LEATHER });
    for (const x of [-.27, .27]) {
      forward(kit, [x, .33, -.66], [[.2, -.02], [.215, .04], [.21, .1], [.19, .15], [.17, .16], [.15, .13]], { n: 18, color: byLevel({ 3: C.GOLD, default: BRASS }), capStart: true });
      forward(kit, [x, .33, -.79], [[.15, 0], [.13, .04], [.08, .07], [0, .08]], { n: 18, color: bands(T, T, TL), capStart: true });
      dome(kit, x + (x < 0 ? -.2 : .2), .33, -.62, .035, BRASS, 1);
    }
    kit.tube([[-.08, .35, -.74], [-.03, .38, -.76], [.03, .38, -.76], [.08, .35, -.74]], .03, { n: 10, color: BRASS });
    roundBox(kit, { pos: [0, .33, .68], rot: [0, 0, 0], len: .06, w: .22, h: .16, steps: 4, m: 16, ex: 3.5, cols: [BRASS] });
  });
  // Knight's helm: a domed bowl, cheek guards, a nasal and a plume ridge.
  outfit('HatHelm', { smooth: HARD, tint: 'B23A48', kind: 'outfit', slot: 'head' }, kit => {
    kit.lathe([[.7, .18], [.72, .36], [.7, .56], [.6, .76], [.4, .9], [0, .96]], { n: 28, color: () => IRON, capStart: true });
    torus(kit, { pos: [0, .2, 0], R: .71, r: .05, n: 28, color: BRASS });
    for (const s of [-1, 1]) blade(kit, { pos: [s * .66, .24, -.18], rot: [PI, 0, 0], len: .5, w: .36, th: .045, tip: .55, belly: .25, cols: [IRON] });
    blade(kit, { pos: [0, .26, -.71], rot: [PI, 0, 0], len: .3, w: .1, th: .03, tip: .6, belly: .2, cols: [IRON] });
    blade(kit, { pos: [0, .9, .1], rot: [-.25, PI / 2, 0], len: .85, w: .5, th: .07, tip: .2, belly: .4, camber: .08, cols: [T, TL] });
  });
  // Miner's helm: a brass shell with a rolled rim and a lamp at the brow.
  outfit('HatMiner', { smooth: HARD, tint: 'C9A227', kind: 'outfit', slot: 'head' }, kit => {
    kit.lathe([[.62, .22], [.82, .24], [.86, .3], [.7, .32], [.68, .5], [.6, .72], [.38, .86], [0, .9]], { n: 28, color: bands(TD, TD, TD, T, T, TL, TL), capStart: true });
    forward(kit, [0, .52, -.66], [[.14, -.12], [.16, 0], [.12, .06], [0, .07]], { n: 20, color: bands(IRON, IRON, GLASS), capStart: true });
    torus(kit, { pos: [0, .52, -.7], rot: [PI / 2, 0, 0], R: .15, r: .03, n: 20, color: BRASS });
  });
  // Sou'wester: oilskin crown, brim drooping at the back.
  outfit('HatSouwester', { smooth: CLOTH, tint: 'E9B949', kind: 'outfit', slot: 'head' }, kit => {
    const droop = level => level <= 4 ? 1 : 0;
    kit.lathe([[.62, .44], [1.0, .42], [1.14, .4], [1.1, .47], [.9, .5], [.64, .54], [.66, .78], [.5, .96], [.26, 1.04], [0, 1.06]],
      { n: 28, color: bands(T, T, TD, TD, T, T, TL), capStart: true, lift: (level, i) => -.22 * droop(level) * Math.max(0, Math.sin(i * 2 * PI / 28)) ** 1.4 });
    torus(kit, { pos: [0, .58, 0], R: .64, r: .04, n: 28, color: TD });
  });
  // Tricorn: a felt brim cocked up at three points, gold piping.
  outfit('HatTricorn', { smooth: CLOTH, tint: '1F1A2B', kind: 'outfit', slot: 'head' }, kit => {
    const up = i => .26 * Math.max(0, Math.cos(3 * (i * 2 * PI / 30 + PI / 2))) ** 1.6;
    kit.lathe([[.6, .5], [.95, .52], [1.12, .56], [1.08, .62], [.86, .6], [.63, .62], [.64, .86], [.46, 1.02], [0, 1.06]],
      { n: 30, color: byLevel({ 2: C.GOLD, default: T }), capStart: true, lift: (level, i) => level >= 1 && level <= 4 ? up(i) * (level / 2) : 0 });
    dome(kit, .5, .78, -.52, .06, C.GOLD, 1);
  });
  // Feathered beret: a soft tilted crown and a long cambered plume.
  outfit('HatFeather', { smooth: CLOTH, tint: 'C2185B', kind: 'outfit', slot: 'head' }, kit => {
    kit.group({ rot: [0, 0, .12] }, () => kit.lathe([[.66, .4], [.78, .5], [.82, .6], [.68, .74], [.4, .84], [0, .86]], { n: 26, sz: .95, color: bands(TD, T, T, TL, TL), capStart: true }));
    blade(kit, { pos: [.42, .66, .1], rot: [.35, 0, -.6], len: 1.15, w: .26, th: .03, tip: .12, belly: .35, camber: .08, cols: [C.CLOTH, TL] });
    dome(kit, .44, .66, .06, .08, C.GOLD, 1);
  });
  // Hood: a deep cowl raised over the head, open at the face, a rolled rim
  // and a drape falling to the shoulders behind.
  outfit('HatHood', { smooth: CLOTH, tint: '2F5233', kind: 'outfit', slot: 'head' }, kit => {
    // Lofted C-shaped cowl: back and sides closed, the face left open in front.
    const rows = [[.98, .1, .2], [.9, .38, .3], [.74, .62, .5], [.5, .76, .7], [.2, .8, .8], [-.15, .82, .84], [-.45, .84, .9], [-.62, .86, .95]];
    const k = 10, th = .07, zc = .12;
    kit.group({ pos: [0, rows[0][0], 0], rot: [PI / 2, 0, 0] }, () => kit.loft(rows.map(([y, R, phi]) => {
      const pts = [];
      for (let i = 0; i < k; i++) { const a = -(PI - phi) + i * 2 * (PI - phi) / (k - 1); pts.push([R * Math.sin(a), zc + R * Math.cos(a)]); }
      for (let i = k - 1; i >= 0; i--) { const a = -(PI - phi) + i * 2 * (PI - phi) / (k - 1), r = Math.max(.02, R - th); pts.push([r * Math.sin(a), zc + r * Math.cos(a)]); }
      return { z: rows[0][0] - y, points: pts };
    }), { color: s => s >= 6 ? TD : s <= 1 ? TL : T, capEnd: false }));
    sheet(kit, { top: -.45, len: .6, w: t => 1.5 + .45 * t, th: () => .06, depth: (t, x) => .66 + .12 * x * x + .1 * t, steps: 4, m: 16, cols: [T, TD] });
  });
  // Mage's hat: a tall cone bent back at the tip over a broad brim, rune band.
  outfit('HatMage', { smooth: CLOTH, tint: '4B2C7A', kind: 'outfit', slot: 'head' }, kit => {
    const bend = (level, i) => level >= 7 ? [0, .14 * (level - 6) ** 1.5] : [0, 0];
    kit.lathe([[.6, .48], [1.05, .5], [1.2, .55], [1.1, .6], [.6, .58], [.56, .74], [.4, 1.08], [.24, 1.38], [.1, 1.62], [0, 1.7]],
      { n: 28, color: byLevel({ 0: TD, 1: TD, 2: TD, 3: TD, default: T }), capStart: true, wobble: bend });
    torus(kit, { pos: [0, .7, 0], R: .55, r: .06, n: 28, color: C.RUNE });
    kit.blob(0, .96, -.42, .07, .07, .05, { sub: 2, color: () => C.RUNE });
  });
  // Straw hat: a woven wide brim (banded weave) and a ribbon.
  outfit('HatStraw', { smooth: CLOTH, tint: 'C0392B', kind: 'outfit', slot: 'head' }, kit => {
    kit.lathe([[.6, .48], [.9, .5], [1.2, .52], [1.38, .55], [1.32, .6], [1.0, .58], [.64, .6], [.62, .8], [.5, .96], [.26, 1.02], [0, 1.03]],
      { n: 30, color: byLevel({ 1: C.PLANK, 8: C.PLANK, default: STRAW }), capStart: true });
    torus(kit, { pos: [0, .68, 0], R: .625, r: .06, n: 28, color: T });
  });

  // =========================================================================
  // Torso pieces (origin = UpperTorso centre).
  // =========================================================================
  // Work apron: a heavy leather bib and skirt wrapping the front, neck strap,
  // a pocket band and brass rivets.
  outfit('Apron', { smooth: CLOTH, tint: '3A2A1E', kind: 'outfit', slot: 'torso' }, kit => {
    sheet(kit, { top: .6, len: 2.9, steps: 10, m: 16, w: t => t < .25 ? 1.1 + t * 1.2 : 1.4 + (t - .25) * .45, th: () => .05,
      depth: (t, x) => -.56 - (t > .35 ? .06 : 0) + .1 * x * x, cols: [T, T, T, T, TD, T, T, T, T, TL] });
    torus(kit, { pos: [0, .74, -.06], rot: [-.2, 0, 0], R: .5, r: .035, n: 24, sx: 1, sz: 1.15, color: LEATHER });
    for (const x of [-.48, .48]) dome(kit, x, .54, -.6, .05, BRASS, 1);
  });
  // Cloak: a long folded cape from a mantle collar to the ankles.
  outfit('Cloak', { smooth: CLOTH, tint: '00838F', kind: 'outfit', slot: 'torso' }, kit => {
    // QC M3: the cape hangs from the shoulders (wide enough to cover the shoulder
    // line and the upper arms' backs) close to the back, with a heavy lined hem.
    sheet(kit, { top: .8, len: 3.8, steps: 12, m: 20, w: t => 2.5 + t * .8, th: t => .07 + .03 * t,
      depth: (t, x) => .53 + .14 * t + .1 * x * x + .05 * Math.sin(x * 5.2) * t, cols: [TD, T, T, T, T, T, T, T, T, T, T, TD] });
    // Shoulder drape: a short lathe collar over the shoulders, opaque all round.
    kit.lathe([[.62, .92], [1.0, .84], [1.32, .66], [1.42, .48], [1.36, .44], [1.2, .58], [.9, .74], [.58, .8]],
      { n: 30, sx: 1, sz: .56, color: byLevel({ 2: TD, 3: TD, default: T }), capStart: true, capEnd: true });
    dome(kit, -.62, .72, -.46, .08, C.GOLD, 1); dome(kit, .62, .72, -.46, .08, C.GOLD, 1);
  });
  // Mantle: a short shoulder cape (scholars, officials, keepers).
  outfit('Mantle', { smooth: CLOTH, tint: '1F2F4F', kind: 'outfit', slot: 'torso' }, kit => {
    kit.lathe([[.62, .9], [.98, .8], [1.3, .62], [1.5, .38], [1.56, .2], [1.5, .16], [1.38, .3], [1.18, .52], [.88, .7], [.56, .78]],
      { n: 30, sx: 1, sz: .52, color: byLevel({ 3: TL, 4: C.GOLD, 5: C.GOLD, default: T }), capStart: true, capEnd: true });
    dome(kit, 0, .74, -.42, .09, C.GOLD, 1);
  });
  // Satchel: a leather bag on the right hip with a cross-body strap.
  outfit('Satchel', { smooth: CLOTH, tint: '7A4E2D', kind: 'outfit', slot: 'torso' }, kit => {
    const strap = [];
    for (let i = 0; i <= 14; i++) { const t = i / 14, a = -PI * .5 + t * PI * 2; strap.push([Math.sin(a) * 1.08 * (1 - .15 * Math.cos(a)), .62 - t * 1.62 + .1 * Math.sin(t * PI), Math.cos(a) * .6]); }
    kit.tube(strap, .045, { n: 10, color: LEATHER });
    roundBox(kit, { pos: [1.02, -1.15, -.12], rot: [0, PI / 2, 0], len: .26, w: .7, h: .56, steps: 5, m: 16, cols: [T] });
    dome(kit, 1.02, -1.08, -.3, .05, BRASS, 1);
  });
  // Tabard: a guard's surcoat panel over the chest with a crest boss.
  outfit('Tabard', { smooth: CLOTH, tint: 'B23A48', kind: 'outfit', slot: 'torso' }, kit => {
    sheet(kit, { top: .7, len: 2.45, steps: 9, m: 16, w: t => 1.25 + .1 * t, th: () => .045, depth: (t, x) => -.56 - .02 * t + .08 * x * x, cols: [T, T, TL, T, T, T, T, T, TD] });
    forward(kit, [0, .1, -.6], [[.24, 0], [.2, .04], [.1, .07], [0, .08]], { n: 20, color: bands(C.GOLD, C.GOLD, TL), capStart: true });
    for (const s of [-1, 1]) kit.group({ pos: [s * 1.3, .62, 0] }, () => kit.lathe([[.52, -.18], [.54, 0], [.46, .18], [.26, .3], [0, .34]], { n: 24, color: bands(IRON, IRON, IRON, BRASS), capStart: true }));
  });
  // Tool belt: a thick belt with pouches and a buckle (worn at the waist).
  outfit('ToolBelt', { smooth: HARD, tint: '5A4030', kind: 'outfit', slot: 'torso' }, kit => {
    torus(kit, { pos: [0, -.8, 0], R: 1, r: .09, n: 32, m: 10, sx: 1.04, sz: .55, color: T });
    kit.group({ pos: [0, -.8, -.6] }, () => kit.lathe([[.14, -.12], [.15, .12], [0, .14]], { n: 12, sz: .4, color: () => BRASS, capStart: true }));
    for (const x of [-.72, .76]) roundBox(kit, { pos: [x, -.98, -.52], rot: [0, 0, 0], len: .2, w: .34, h: .4, steps: 4, m: 16, cols: [TD] });
  });
  // Scarf: a knitted neck wrap with a tail over the chest.
  outfit('Scarf', { smooth: CLOTH, tint: 'FFD166', kind: 'outfit', slot: 'torso' }, kit => {
    torus(kit, { pos: [0, .78, 0], R: .62, r: .13, n: 28, m: 12, sx: 1.05, sz: .9, color: T });
    sheet(kit, { top: .72, len: 1.05, w: () => .3, th: () => .05, depth: (t) => -.62 - .04 * t, steps: 5, m: 12, cols: [T, TL, T, TL, T], xoff: t => .32 + .05 * t });
  });

  // =========================================================================
  // Hand props (origin = the grip; the shaft runs down -Y).
  // =========================================================================
  // Smith's hammer: ash handle, banded iron head with a domed face.
  outfit('PropHammer', { smooth: HARD, tint: '4A4A4A', kind: 'outfit', slot: 'hand' }, kit => {
    rod(kit, [[0, .3, 0], [0, -.4, 0], [0, -1.2, 0]], .085, WOOD, 12, .85);
    roundBox(kit, { pos: [0, -1.28, 0], rot: [0, PI / 2, 0], len: .78, w: .34, h: .34, steps: 6, m: 16, ex: 3.2, shape: t => [1 - .15 * Math.abs(t - .5), 1 - .15 * Math.abs(t - .5)], cols: [IRON, T, T, T, T, IRON] });
    torus(kit, { pos: [0, -1.06, 0], R: .1, r: .03, n: 16, color: BRASS });
  });
  // Angler's rod: cork grip, brass reel, a tapered blank to a fine tip.
  outfit('PropRod', { smooth: HARD, tint: '8B5A2B', kind: 'outfit', slot: 'hand' }, kit => {
    rod(kit, [[0, -.35, 0], [0, 0, 0], [0, .4, 0]], .075, C.CLOTH, 12);
    rod(kit, [[0, .4, 0], [0, 1.6, -.04], [0, 2.8, -.16], [0, 3.9, -.36]], (i, m) => .055 * (1 - .78 * i / (m - 1)), T, 10);
    kit.group({ pos: [.13, .1, 0], rot: [0, 0, PI / 2] }, () => kit.lathe([[.1, -.06], [.13, -.04], [.13, .04], [.1, .06], [0, .07]], { n: 16, color: bands(BRASS, BRASS, IRON), capStart: true }));
    for (const y of [1.2, 2.2, 3.1]) torus(kit, { pos: [0, y, -.06 - (y - 1) * .1], R: .05, r: .015, n: 12, m: 8, color: BRASS });
  });
  // Scholar's open tome: two cambered page blocks in a leather cover.
  outfit('PropTome', { smooth: CLOTH, tint: '5B3F8C', kind: 'outfit', slot: 'hand' }, kit => {
    for (const s of [-1, 1]) {
      roundBox(kit, { pos: [s * .3, -.2, -.42], rot: [-.55, s * .2, 0], len: .62, w: .6, h: .08, steps: 5, m: 16, ex: 3, shape: t => [1, 1 + .4 * Math.sin(PI * t)], cols: [PAPER] });
      roundBox(kit, { pos: [s * .31, -.24, -.38], rot: [-.55, s * .2, 0], len: .7, w: .66, h: .03, steps: 4, m: 16, ex: 3, cols: [T] });
    }
    rod(kit, [[0, -.43, -.17], [0, -.06, -.66]], .04, TD, 10);
    blade(kit, { pos: [0, -.18, -.5], rot: [-.55 - PI / 2, 0, 0], len: .55, w: .05, th: .008, tip: .8, belly: .1, m: 10, cols: [C.CRIMSON] });
  });
  // Ledger: a closed account book with a banded spine and a brass clasp.
  outfit('PropLedger', { smooth: HARD, tint: '1F2F4F', kind: 'outfit', slot: 'hand' }, kit => {
    roundBox(kit, { pos: [0, -.25, -.2], rot: [0, 0, 0], len: .26, w: .72, h: .95, steps: 5, m: 16, ex: 3.4, cols: [T, PAPER, PAPER, PAPER, T] });
    torus(kit, { pos: [-.36, -.25, -.2], rot: [0, 0, PI / 2], R: .12, r: .03, n: 16, color: BRASS });
    dome(kit, .36, -.25, -.2, .06, BRASS, 1);
  });
  // Lantern: a brass cage, a glass globe, a cap and a bail handle.
  outfit('PropLantern', { smooth: HARD, tint: 'F9CC77', kind: 'outfit', slot: 'hand' }, kit => {
    torus(kit, { pos: [0, -.12, 0], rot: [0, 0, PI / 2], R: .16, r: .025, n: 16, color: IRON });
    kit.group({ pos: [0, -.75, 0] }, () => kit.lathe([[.26, -.34], [.28, -.3], [.22, -.26], [.24, 0], [.22, .22], [.16, .28], [.2, .32], [.12, .42], [0, .46]],
      { n: 20, color: byLevel({ 0: IRON, 1: IRON, 2: GLASS, 3: GLASS, 4: IRON, 5: IRON, default: BRASS }), capStart: true }));
    for (let i = 0; i < 4; i++) { const a = i * PI / 2 + PI / 4; rod(kit, [[Math.cos(a) * .25, -1.06, Math.sin(a) * .25], [Math.cos(a) * .25, -.5, Math.sin(a) * .25]], .02, BRASS, 10); }
    kit.blob(0, -.78, 0, .1, .15, .1, { sub: 2, color: () => T });
  });
  // Rune staff: a twisted shaft, gold claws holding a glowing crystal.
  outfit('PropStaff', { smooth: HARD, tint: 'C77DFF', kind: 'outfit', slot: 'hand' }, kit => {
    rod(kit, [[0, -1.7, 0], [0, -.6, .02], [0, .6, -.02], [0, 2.6, 0]], .085, WOOD, 12, .8);
    torus(kit, { pos: [0, 2.55, 0], R: .1, r: .035, n: 16, color: C.GOLD });
    for (let i = 0; i < 3; i++) { const a = i * 2 * PI / 3; rod(kit, [[Math.cos(a) * .08, 2.58, Math.sin(a) * .08], [Math.cos(a) * .2, 2.8, Math.sin(a) * .2], [Math.cos(a) * .12, 3.06, Math.sin(a) * .12]], .03, C.GOLD, 10, .4); }
    kit.group({ pos: [0, 2.95, 0] }, () => kit.lathe([[0, -.24], [.16, -.06], [.15, .08], [0, .3]], { n: 12, color: bands(T, TL, TL) }));
  });
  // Guard's spear: an ash shaft, a fullered leaf blade, a brass collar.
  outfit('PropSpear', { smooth: HARD, tint: 'D8DEE6', kind: 'outfit', slot: 'hand' }, kit => {
    rod(kit, [[0, -1.9, 0], [0, 0, 0], [0, 2.5, 0]], .07, WOOD, 12, .9);
    kit.group({ pos: [0, 2.5, 0] }, () => kit.lathe([[.08, -.05], [.1, .05], [.09, .16], [.06, .2]], { n: 14, color: () => BRASS, capStart: true }));
    blade(kit, { pos: [0, 2.68, 0], rot: [0, 0, 0], len: .9, w: .32, th: .05, tip: .04, belly: .35, cols: [T] });
    dome(kit, 0, -1.92, 0, .08, IRON, 1);
  });
  // Sword: a fullered blade, a curved crossguard, a wrapped grip, a pommel.
  outfit('PropSword', { smooth: HARD, tint: 'D8DEE6', kind: 'outfit', slot: 'hand' }, kit => {
    rod(kit, [[0, .3, 0], [0, -.3, 0]], .07, LEATHER, 12);
    dome(kit, 0, .36, 0, .1, C.GOLD, 2);
    rod(kit, [[-.38, -.28, 0], [-.18, -.34, 0], [0, -.36, 0], [.18, -.34, 0], [.38, -.28, 0]], .045, C.GOLD, 10);
    blade(kit, { pos: [0, -.36, 0], rot: [PI, 0, 0], len: 2.1, w: .26, th: .045, tip: .05, belly: .12, steps: 8, cols: [T] });
  });
  // Pickaxe: a hickory haft and a curved double-pointed head.
  outfit('PropPickaxe', { smooth: HARD, tint: '5B3F8C', kind: 'outfit', slot: 'hand' }, kit => {
    rod(kit, [[0, .25, 0], [0, -.7, 0], [0, -1.55, 0]], .08, WOOD, 12, .9);
    rod(kit, [[-.78, -1.38, 0], [-.4, -1.58, 0], [0, -1.64, 0], [.4, -1.58, 0], [.78, -1.38, 0]], (i, m) => .1 * (1 - .75 * Math.abs(i - (m - 1) / 2) / ((m - 1) / 2)), T, 12);
    torus(kit, { pos: [0, -1.62, 0], R: .1, r: .045, n: 16, color: IRON });
  });
  // Bow saw: a wooden frame, a steel blade and a twisted tension cord.
  outfit('PropSaw', { smooth: HARD, tint: 'BFC5CC', kind: 'outfit', slot: 'hand' }, kit => {
    rod(kit, [[0, .2, 0], [0, -.25, 0]], .08, WOOD, 12);
    rod(kit, [[0, -.25, 0], [-.1, -.8, 0], [0, -1.4, 0], [.25, -1.6, 0]], .05, WOOD, 10);
    blade(kit, { pos: [.05, -.25, -.02], rot: [PI, 0, -.08], len: 1.35, w: .14, th: .022, tip: .8, belly: .05, steps: 8, m: 16, cols: [T] });
    rod(kit, [[0, -.25, .04], [-.04, -.8, .05], [.05, -1.35, .04]], .015, PAPER, 10);
  });
  // Produce crate: a slatted box heaped with fruit (carried on the hip).
  outfit('PropCrate', { smooth: HARD, tint: 'C0392B', kind: 'outfit', slot: 'hand' }, kit => {
    roundBox(kit, { pos: [-.7, -.05, -.6], rot: [0, 0, 0], len: .9, w: 1.2, h: .8, steps: 6, m: 16, ex: 4, cols: [C.PLANK, C.BARK, C.PLANK, C.PLANK, C.BARK, C.PLANK] });
    for (const [x, z] of [[-1.0, -.4], [-.7, -.55], [-.4, -.42], [-.85, -.8], [-.52, -.78]]) kit.blob(x, .42, z, .17, .16, .17, { sub: 1, color: n => n[1] > .55 ? TL : T });
  });
  // Scroll: a parchment roll on turned handles with a wax seal.
  outfit('PropScroll', { smooth: HARD, tint: 'C9A227', kind: 'outfit', slot: 'hand' }, kit => {
    kit.group({ pos: [0, -.1, -.15], rot: [0, 0, PI / 2] }, () => kit.lathe([[.06, -.72], [.09, -.68], [.07, -.58], [.16, -.56], [.17, 0], [.16, .56], [.07, .58], [.09, .68], [.06, .72], [0, .74]],
      { n: 16, color: byLevel({ 0: WOOD, 1: WOOD, 2: WOOD, 7: WOOD, 8: WOOD, 9: WOOD, default: PAPER }), capStart: true }));
    kit.blob(0, -.1, -.33, .1, .1, .04, { sub: 2, color: () => T });
  });
  // Herald's horn: a curved brass horn flaring to a bell, a coloured cord.
  outfit('PropHorn', { smooth: HARD, tint: 'FFD166', kind: 'outfit', slot: 'hand' }, kit => {
    const pts = []; for (let i = 0; i <= 8; i++) { const t = i / 8; pts.push([0, -.1 - .25 * Math.sin(t * PI), -.1 - t * 1.0]); }
    kit.tube(pts, i => .04 + .1 * (i / 8) ** 2.2, { n: 14, color: C.GOLD, capStart: true, capEnd: false });
    forward(kit, [0, -.1, -1.1], [[.14, 0], [.24, .1], [.3, .16], [.25, .17], [.12, .06]], { n: 20, color: () => C.GOLD });
    torus(kit, { pos: [0, -.2, -.55], rot: [PI / 2, 0, 0], R: .085, r: .03, n: 14, color: T });
  });
  // Fire poker: an iron rod with a hooked, ember-hot tip (Beaconkeeper).
  outfit('PropPoker', { smooth: HARD, tint: 'FF8A3D', kind: 'outfit', slot: 'hand' }, kit => {
    torus(kit, { pos: [0, .3, 0], rot: [0, 0, PI / 2], R: .12, r: .03, n: 16, color: IRON });
    rod(kit, [[0, .18, 0], [0, -1.6, 0], [0, -2.0, -.05]], .04, IRON, 10);
    rod(kit, [[0, -2.0, -.05], [0, -2.16, -.16], [0, -2.1, -.3]], .04, T, 10, .6);
  });
  // Shepherd's crook: a long staff curling into a hook.
  outfit('PropCrook', { smooth: HARD, tint: '8B5A2B', kind: 'outfit', slot: 'hand' }, kit => {
    const pts = [[0, -1.8, 0], [0, 0, 0], [0, 2.3, 0]];
    for (let i = 1; i <= 7; i++) { const a = i / 7 * PI * 1.15; pts.push([0, 2.3 + Math.sin(a) * .28, -(1 - Math.cos(a)) * .28]); }
    kit.tube(pts, .07, { n: 12, color: T });
  });
  // Hoe: a long haft with an angled iron blade.
  outfit('PropHoe', { smooth: HARD, tint: '8D6E63', kind: 'outfit', slot: 'hand' }, kit => {
    rod(kit, [[0, .3, 0], [0, -1.0, 0], [0, -2.3, 0]], .065, WOOD, 12);
    blade(kit, { pos: [0, -2.28, 0], rot: [-PI / 2 - .3, 0, 0], len: .5, w: .44, th: .03, tip: .85, belly: .15, m: 12, cols: [IRON, T] });
  });

  return {};
};
