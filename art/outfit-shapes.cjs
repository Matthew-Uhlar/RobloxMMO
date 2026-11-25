// NPC outfits (docs/DEPTH-CONTRACT.md §52, re-authored in §55): hats, hoods,
// helms, aprons, cloaks, mantles, satchels, belts and the trade props the
// townsfolk hold, forged on each client by npc.client.lua through the MeshForge
// outfit API and welded to the server's R15-style rig (the primitive hat / prop
// parts stay as the fallback and are hidden locally once the mesh exists).
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
// §55 organic bar (verify-mesh): 98 % of shading normals (by area) within 15
// degrees of their face, <= 2 % of edges sharper than 35 degrees, every ring
// >= 16 segments. So: lathe profiles are filleted polylines (OK.rounded: every
// corner an arc of <= 20 degrees per level: rolled brims, soft crowns), and
// ribbons, bands and collars are raised ridges inside those profiles (one
// surface, no torus seam); cloth is lofted through stadium sections (broad
// faces split so a wrap or a fold bends them, edges rounded half-circles);
// boxes are rounded rectangles; rings are closed tube loops; rivets and
// buttons are small squashed ellipsoids. TINT faces take the NPC's dye (the
// cloth colour of their look, quantised to NpcStyle.DYES), TINT_DARK /
// TINT_LIGHT its shades; leather, brass, iron, straw, parchment and glass stay fixed.
'use strict';
const OK = require('./organic-kit.cjs');
module.exports = ({ outfit, C, PI }) => {
  const { TINT: T, TINT_DARK: TD, TINT_LIGHT: TL } = C;
  const CLOTH = 55, HARD = 50;
  const LEATHER = C.TIMBER, BRASS = C.BRASS, IRON = C.IRON, STRAW = C.STRAW, PAPER = C.CLOTH, WOOD = C.HANDLE, GLASS = C.GLASS;

  // Filleted profile (no fairing needed: every level turns <= stepDeg).
  const P = (pts, rc, stepDeg = 20, maxLen = Infinity) => OK.rounded(pts, rc, { stepDeg, maxLen });
  const lat = (kit, profile, opts = {}) => kit.lathe(profile, { turn: 1, ...opts });
  // Colour by the face centre's height / radius (continuous fields, not levels).
  const byY = (...stops) => (l, i, c) => { for (const [y, col] of stops) if (c[1] < y) return col; return stops[stops.length - 1][1]; };
  const byR = (...stops) => (l, i, c) => { const r = Math.hypot(c[0], c[2]); for (const [rr, col] of stops) if (r < rr) return col; return stops[stops.length - 1][1]; };
  // A ribbon band raised on a crown wall: profile points from (r, y0) up to
  // (r', y1) with a rounded ridge of height h in between (wall points only).
  const ridge = (r0, y0, r1, y1, h) => [[r0, y0], [r0 + (r1 - r0) * .12 + h, y0 + (y1 - y0) * .18], [r0 + (r1 - r0) * .88 + h, y0 + (y1 - y0) * .82], [r1, y1]];
  // Closed ring (bands, straps, rims): a tube loop of N rings round a circle
  // (or a superellipse of exponent ex) in the local XZ plane.
  const ring = (kit, { pos = [0, 0, 0], rot = [0, 0, 0], R = 1, r = .05, N = 24, n = 16, sx = 1, sz = 1, ex = 2, color = T }) =>
    kit.group({ pos, rot }, () => kit.tube(Array.from({ length: N }, (_, i) => {
      const a = i * 2 * PI / N, c = Math.cos(a), s = Math.sin(a);
      return [Math.sign(c) * Math.abs(c) ** (2 / ex) * R * sx, 0, Math.sign(s) * Math.abs(s) ** (2 / ex) * R * sz];
    }), r, { n, color, closed: true }));
  // Lathe laid along -Z (a lens, a lamp facing forward).
  const forward = (kit, pos, profile, opts) => kit.group({ pos, rot: [-PI / 2, 0, 0] }, () => lat(kit, profile, opts));
  // A small squashed dome (rivet, button, boss, stud) bulging along local +Y of `rot`.
  const knob = (kit, pos, r, h, color, rot = [0, 0, 0]) => kit.group({ pos, rot }, () => kit.blob(0, 0, 0, r, Math.max(h, r * .65), r, { sub: 2, color: () => color }));
  // Smooth tapered tube along a polyline (faired; rounded end rims).
  const rod = (kit, pts, r, color, opts = {}) => {
    const m = pts.length;
    kit.tube(pts, i => typeof r === 'function' ? r(i, m) : r, { n: 16, color, ...opts });
  };
  const span = (cols, s, count) => cols[Math.max(0, Math.min(cols.length - 1, Math.floor(s * cols.length / count)))];
  // Lofted cloth (aprons, cloaks, tabards, tails): sections run down -Y from
  // `top` to `top - len`; each is a stadium `w(t)` wide and `th(t)` thick
  // (broad faces split into kW pieces, rounded edges), pushed to depth
  // `depth(t, x)` (z) so the sheet wraps the body and folds.
  const sheet = (kit, { top = 0, len = 1, w = () => 1, th = () => .05, depth = () => 0, steps = 8, kW = 7, cols = [T], xoff = () => 0, kArc = 4 }) =>
    kit.group({ pos: [0, top, 0], rot: [PI / 2, 0, 0] }, () => kit.loft(
      Array.from({ length: steps + 1 }, (_, s) => {
        const t = s / steps, half = Math.max(w(t) / 2, .03), tt = Math.min(Math.max(th(t) / 2, .015), half * .9);
        // pitch +90 maps local (x, y, z) -> (x, -z, y): section y becomes depth z.
        return { z: t * len, points: OK.roundRect(half, tt, tt, { kArc, kW }).map(([x, y]) => [x + xoff(t), depth(t, x) + y]) };
      }), { color: s => span(cols, s, steps + 1) }));
  // Rounded box: rounded-rectangle sections along local +Z (books, pouches, crates, buckles).
  const roundBox = (kit, { pos = [0, 0, 0], rot = [0, 0, 0], len = 1, w = 1, h = 1, rc = .06, steps = 4, kW = 2, kH = 2, kArc = 4, shape = () => [1, 1, 0], cols = [T] }) =>
    kit.group({ pos, rot }, () => kit.loft(
      Array.from({ length: steps + 1 }, (_, s) => {
        const t = s / steps, [sw, sh, oy] = shape(t);
        return { z: t * len - len / 2, points: OK.roundRect(w * sw / 2, h * sh / 2, Math.min(rc, .9 * w * sw / 2, .9 * h * sh / 2), { kArc, kW, kH }).map(([x, y]) => [x, y + (oy || 0)]) };
      }), { color: s => span(cols, s, steps + 1) }));
  // Cambered blade with real thickness (feathers, sword and spear blades,
  // visors): span along local +Y, chord along X, a stadium section whose
  // width follows a smooth leaf curve (root -> belly -> tip).
  const blade = (kit, { pos = [0, 0, 0], rot = [0, 0, 0], len = 1, w = .3, th = .04, tip = .05, root = .55, steps = 8, belly = .3, camber = 0, cols = [T], capRoot = false }) =>
    kit.group({ pos, rot }, () => kit.group({ rot: [-PI / 2, 0, 0] }, () => kit.loft(
      Array.from({ length: steps + 1 }, (_, s) => {
        const t = s / steps;
        const prof = t < belly ? root + (1 - root) * OK.sstep(0, belly, t) : 1 - (1 - tip) * OK.sstep(belly, 1, t) ** 1.1;
        const wt = Math.max(w * prof, .03), tt = Math.min(Math.max(th * Math.sqrt(prof), .012), wt * .4), oy = camber * Math.sin(PI * t);
        return { z: t * len, points: OK.roundRect(wt / 2, tt, tt, { kArc: 4, kW: 2 }).map(([x, y]) => [x, y + oy]) };
      }), { color: s => span(cols, s, steps + 1), capStart: capRoot, capEnd: w * tip > .07 })));

  // =========================================================================
  // Head pieces (origin = head centre; crown top at y 0.6, face at z -0.6).
  // =========================================================================
  // Wayfarer: a wide felt brim with a rolled edge, a pinched crown with a
  // centre crease and a raised ribbon band.
  outfit('HatWayfarer', { smooth: CLOTH, tint: '4A3B2A', kind: 'outfit', slot: 'head' }, kit => {
    const wf = P([[0, .5], [1.2, .53], [1.3, .59], [1.22, .645], [.68, .635], ...ridge(.655, .66, .65, .78, .045), [.645, .98], [.52, 1.15], [0, 1.2]],
      [0, .05, .04, .05, .04, .02, .02, .02, .02, .1, .12, .3]);
    lat(kit, wf, { n: 24, color: (l, i, c) => c[1] < .62 ? TD : Math.hypot(c[0], c[2]) > .672 && c[1] > .66 && c[1] < .79 ? C.CRIMSON : c[1] > 1.02 ? TL : T,
      // The crease: the crown top dips along the front-back line.
      lift: (l, i) => -.07 * OK.sstep(.97, 1.18, wf[l][1]) * Math.cos(i * 2 * PI / 24) ** 2 });
    knob(kit, [.43, .72, -.5], .06, .04, BRASS, [-PI / 2, -.7, 0]);
  });
  // Top hat: a tall flared crown with a gold band and a curled brim.
  outfit('HatTop', { smooth: CLOTH, tint: '1A1A1A', kind: 'outfit', slot: 'head' }, kit => {
    lat(kit, P([[0, .5], [.92, .53], [1.0, .6], [.92, .64], [.6, .63], ...ridge(.585, .7, .59, .88, .04), [.6, 1.4], [.63, 1.52], [0, 1.57]],
      [0, .04, .035, .05, .04, .02, .02, .02, .02, .1, .04, .08]), { n: 24, color: (l, i, c) => c[1] < .62 ? TD : Math.hypot(c[0], c[2]) > .6 && c[1] > .7 && c[1] < .89 ? C.GOLD : T });
  });
  // Flat cap: a soft crown over a cambered visor, a button on top.
  outfit('HatCap', { smooth: CLOTH, tint: '6D4C41', kind: 'outfit', slot: 'head' }, kit => {
    lat(kit, P([[0, .38], [.68, .38], [.72, .55], [.62, .75], [.36, .89], [0, .93]], [0, .06, .14, .14, .2]), { n: 20, sz: 1.05, color: byY([.45, TD], [.78, T], [9, TL]) });
    blade(kit, { pos: [0, .44, -.58], rot: [-1.42, 0, 0], len: .5, w: 1.08, th: .035, tip: .62, root: .9, belly: .25, camber: .05, cols: [TD] });
    knob(kit, [0, .92, 0], .07, .04, TD);
  });
  // Tinker's goggles: a padded strap following the square head, deep brass
  // cups with rolled rims, domed lenses, a nose bridge and a buckle.
  outfit('HatGoggles', { smooth: HARD, tint: '2B2B2B', kind: 'outfit', slot: 'head' }, kit => {
    ring(kit, { pos: [0, .33, 0], R: .66, r: .07, N: 32, ex: 5, color: LEATHER });
    for (const x of [-.27, .27]) {
      forward(kit, [x, .33, -.64], P([[0, -.02], [.2, -.02], [.215, .1], [.19, .15], [.15, .13], [0, .13]], [0, .02, .03, .02, .02]), { n: 20, color: byR([.165, GLASS], [9, BRASS]) });
      forward(kit, [x, .33, -.77], P([[.15, 0], [.12, .045], [0, .07]], [0, .04]), { n: 20, color: () => GLASS });
    }
    rod(kit, [[-.08, .35, -.74], [-.03, .38, -.76], [.03, .38, -.76], [.08, .35, -.74]], .03, BRASS, { capStart: false, capEnd: false });
    roundBox(kit, { pos: [0, .33, .7], len: .06, w: .22, h: .16, rc: .03, steps: 2, kArc: 3, cols: [BRASS] });
  });
  // Knight's helm: a domed bowl over a raised brass brow band, cheek guards,
  // a nasal and a plume crest.
  outfit('HatHelm', { smooth: HARD, tint: 'B23A48', kind: 'outfit', slot: 'head' }, kit => {
    lat(kit, P([[0, .14], [.66, .14], ...ridge(.7, .15, .71, .27, .05), [.72, .42], [.66, .66], [.42, .9], [0, .96]], [0, .03, .02, .02, .02, .1, .2, .2, .25]), {
      n: 24, color: (l, i, c) => c[1] < .29 && Math.hypot(c[0], c[2]) > .705 ? BRASS : IRON });
    for (const s of [-1, 1]) blade(kit, { pos: [s * .66, .24, -.18], rot: [PI, 0, 0], len: .5, w: .36, th: .045, tip: .55, root: .9, belly: .25, cols: [IRON] });
    blade(kit, { pos: [0, .26, -.71], rot: [PI, 0, 0], len: .3, w: .1, th: .03, tip: .6, root: .9, belly: .2, steps: 5, cols: [IRON] });
    blade(kit, { pos: [0, .9, .1], rot: [-.25, PI / 2, 0], len: .85, w: .5, th: .07, tip: .2, root: .6, belly: .4, camber: .08, steps: 9, cols: [T, T, TL] });
  });
  // Miner's helm: a brass shell with a rolled rim and a lamp at the brow.
  outfit('HatMiner', { smooth: HARD, tint: 'C9A227', kind: 'outfit', slot: 'head' }, kit => {
    lat(kit, P([[0, .22], [.8, .23], [.86, .28], [.78, .32], [.69, .34], [.67, .5], [.6, .72], [.38, .86], [0, .9]], [0, .03, .03, .03, .03, .1, .12, .2]), {
      n: 24, color: byY([.33, TD], [.62, T], [9, TL]) });
    forward(kit, [0, .52, -.64], P([[0, -.1], [.14, -.1], [.16, -.02], [.175, .01], [.15, .05], [.12, .06], [0, .07]], [0, .03, .015, .015, .015, .03]), {
      n: 20, color: (l, i, c) => c[1] < -.025 ? IRON : c[1] < .045 && Math.hypot(c[0], c[2]) > .14 ? BRASS : GLASS });
  });
  // Sou'wester: oilskin crown with a band, a brim drooping long at the back.
  outfit('HatSouwester', { smooth: CLOTH, tint: 'E9B949', kind: 'outfit', slot: 'head' }, kit => {
    const sw = P([[0, .44], [1.04, .42], [1.14, .43], [1.08, .48], [.9, .5], [.66, .54], ...ridge(.645, .56, .655, .64, .03), [.66, .78], [.5, .96], [0, 1.06]],
      [0, .04, .035, .04, .06, .03, .015, .015, .03, .1, .12, .3]);
    lat(kit, sw, { n: 24, color: (l, i, c) => c[1] < .3 ? TD : c[1] > .55 && c[1] < .65 && Math.hypot(c[0], c[2]) > .65 ? TD : c[1] > .85 ? TL : T,
      // The brim droops long at the back (+Z), level in front.
      lift: (l, i) => -.22 * OK.sstep(.66, 1.1, sw[l][0]) * (sw[l][1] < .56 ? 1 : 0) * Math.max(0, Math.sin(i * 2 * PI / 24)) ** 1.4 });
  });
  // Tricorn: a felt brim cocked up at three points, gold piping on the rim.
  outfit('HatTricorn', { smooth: CLOTH, tint: '1F1A2B', kind: 'outfit', slot: 'head' }, kit => {
    const up = a => .26 * ((1 + Math.cos(3 * (a + PI / 2))) / 2) ** 2;
    const profile = P([[0, .5], [.6, .5], [1.02, .52], [1.12, .57], [1.06, .62], [.86, .6], [.63, .62], [.64, .86], [.46, 1.02], [0, 1.06]], [0, 0, .04, .035, .04, .05, .1, .15, .25], 20, .15);
    lat(kit, profile, { n: 30, color: (l, i, c) => Math.hypot(c[0], c[2]) > 1.04 ? C.GOLD : T,
      // The cock: radius-weighted lift (0 inside the crown, full at the rim).
      lift: (l, i) => up(i * 2 * PI / 30) * OK.sstep(.62, 1.05, profile[l][0]) });
    knob(kit, [.48, .8, -.5], .06, .04, C.GOLD, [-PI / 2 + .2, -.7, 0]);
  });
  // Feathered beret: a soft tilted crown and a long cambered plume.
  outfit('HatFeather', { smooth: CLOTH, tint: 'C2185B', kind: 'outfit', slot: 'head' }, kit => {
    kit.group({ rot: [0, 0, .12] }, () => lat(kit, P([[0, .4], [.7, .41], [.82, .56], [.68, .74], [.4, .84], [0, .86]], [0, .06, .12, .14, .2]), { n: 20, sz: .95, color: byY([.47, TD], [.72, T], [9, TL]) }));
    blade(kit, { pos: [.42, .66, .1], rot: [.35, 0, -.6], len: 1.15, w: .26, th: .03, tip: .12, root: .3, belly: .35, camber: .08, steps: 9, cols: [C.CLOTH, C.CLOTH, TL] });
    knob(kit, [.46, .68, .04], .08, .05, C.GOLD, [0, 0, -.7]);
  });
  // Hood: a deep cowl over the head, open at the face, and a drape falling to
  // the shoulders behind.
  outfit('HatHood', { smooth: CLOTH, tint: '2F5233', kind: 'outfit', slot: 'head' }, kit => {
    // Lofted C-shaped cowl (stadium arcs bent round the head): back and sides
    // closed, the face open in front; rows [y, radius, open half-angle].
    const rows = [[.96, .2, .2], [.9, .38, .3], [.74, .62, .5], [.5, .76, .7], [.2, .8, .8], [-.15, .82, .84], [-.45, .84, .9], [-.62, .86, .95]];
    const th = .08, zc = .12, kW = 14;
    kit.group({ pos: [0, rows[0][0], 0], rot: [PI / 2, 0, 0] }, () => kit.loft(rows.map(([y, R, phi]) => {
      const sweep = PI - phi, rr = R - th / 2;
      const pts = OK.roundRect(sweep * rr, th / 2, th / 2, { kArc: 4, kW }).map(([x, yy]) => {
        const a = x / rr, rad = rr + yy; return [rad * Math.sin(a), zc + rad * Math.cos(a)];
      });
      return { z: rows[0][0] - y, points: pts };
    }), { color: s => s >= 6 ? TD : s <= 1 ? TL : T, capStart: false }));
    // The gathered crown: a soft knot closing the cowl's top.
    kit.blob(0, .93, .12, .2, .12, .2, { sub: 2, color: () => TL });
    sheet(kit, { top: -.45, len: .6, w: t => 1.5 + .45 * t, th: () => .06, depth: (t, x) => .66 + .12 * x * x + .1 * t, steps: 4, cols: [T, TD] });
  });
  // Mage's hat: a tall cone bent back at the tip over a broad brim, a rune band.
  outfit('HatMage', { smooth: CLOTH, tint: '4B2C7A', kind: 'outfit', slot: 'head' }, kit => {
    const profile = P([[0, .48], [1.08, .5], [1.18, .56], [1.08, .6], [.62, .58], ...ridge(.565, .62, .55, .78, .045), [.4, 1.08], [.24, 1.38], [.1, 1.62], [0, 1.72]],
      [0, .04, .035, .05, .04, .02, .02, .02, .02, .2, .15, .06]);
    lat(kit, profile, { n: 24, color: (l, i, c) => c[1] < .6 ? TD : c[1] > .62 && c[1] < .79 && Math.hypot(c[0], c[2]) > .57 ? C.RUNE : T,
      wobble: (l) => [0, .5 * Math.max(0, profile[l][1] - 1.05) ** 2] });
    knob(kit, [0, .95, -.44], .07, .04, C.RUNE, [-PI / 2 + .15, 0, 0]);
  });
  // Straw hat: a woven wide brim (soft rings of plank-tone weave) and a ribbon.
  outfit('HatStraw', { smooth: CLOTH, tint: 'C0392B', kind: 'outfit', slot: 'head' }, kit => {
    lat(kit, P([[0, .48], [1.25, .52], [1.38, .56], [1.3, .61], [1.0, .59], [.66, .6], ...ridge(.63, .62, .625, .76, .05), [.62, .8], [.5, .96], [0, 1.03]],
      [0, .05, .04, .05, .06, .03, .02, .02, .02, .03, .14, .3]), {
      n: 24, color: (l, i, c) => { const r = Math.hypot(c[0], c[2]); if (c[1] > .62 && c[1] < .77 && r > .64) return T; return (r > .7 && r < 1.2 && Math.floor(r * 9) % 3 === 0) || (c[1] > .8 && Math.floor(c[1] * 22) % 3 === 0) ? C.PLANK : STRAW; } });
  });

  // =========================================================================
  // Torso pieces (origin = UpperTorso centre).
  // =========================================================================
  // Work apron: a heavy leather bib and skirt wrapping the front, a neck strap
  // and brass rivets at the bib corners.
  outfit('Apron', { smooth: CLOTH, tint: '3A2A1E', kind: 'outfit', slot: 'torso' }, kit => {
    sheet(kit, { top: .6, len: 2.9, steps: 12, w: t => 1.1 + .3 * OK.sstep(0, .3, t) + .13 * t, th: () => .05,
      depth: (t, x) => -.56 - .06 * OK.sstep(.25, .45, t) + .1 * x * x + .015 * Math.sin(x * 9) * t, cols: [T, T, T, T, T, TD, T, T, T, T, T, TL, TL] });
    ring(kit, { pos: [0, .74, -.06], rot: [-.2, 0, 0], R: .5, r: .035, N: 24, sz: 1.15, color: LEATHER });
    for (const x of [-.48, .48]) knob(kit, [x, .54, -.6], .05, .035, BRASS, [-PI / 2, 0, 0]);
  });
  // Cloak: a long folded cape from a mantle collar to the ankles.
  outfit('Cloak', { smooth: CLOTH, tint: '00838F', kind: 'outfit', slot: 'torso' }, kit => {
    sheet(kit, { top: .8, len: 3.8, steps: 8, kW: 9, w: t => 2.5 + t * .8, th: t => .07 + .03 * t,
      depth: (t, x) => .53 + .14 * t + .1 * x * x + .06 * Math.sin(x * 4.6) * t, cols: [TD, T, T, T, T, T, T, T, T, T, TD] });
    // Shoulder drape: a short lathe collar over the shoulders, a rolled hem.
    lat(kit, P([[.6, .94], [1.02, .85], [1.34, .66], [1.44, .5], [1.38, .44], [1.2, .58], [.9, .74], [.58, .82]], [0, .25, .2, .05, .05, .2, .2]), {
      n: 28, sx: 1, sz: .56, color: (l, i, c) => c[1] < .55 ? TD : T, capStart: true, capEnd: true });
    for (const x of [-.62, .62]) knob(kit, [x, .72, -.46], .08, .05, C.GOLD, [-PI / 2, 0, 0]);
  });
  // Mantle: a short shoulder cape (scholars, officials, keepers) with a gold hem.
  outfit('Mantle', { smooth: CLOTH, tint: '1F2F4F', kind: 'outfit', slot: 'torso' }, kit => {
    lat(kit, P([[.62, .9], [.98, .8], [1.32, .6], [1.5, .36], [1.56, .2], [1.48, .15], [1.38, .3], [1.18, .52], [.88, .7], [.56, .78]], [0, .3, .3, .2, .04, .04, .2, .2, .2]), {
      n: 28, sx: 1, sz: .52, color: (l, i, c) => c[1] < .3 ? C.GOLD : c[1] < .42 ? TL : T, capStart: true, capEnd: true });
    knob(kit, [0, .74, -.43], .09, .05, C.GOLD, [-PI / 2, 0, 0]);
  });
  // Satchel: a leather bag on the right hip with a cross-body strap and a flap buckle.
  outfit('Satchel', { smooth: CLOTH, tint: '7A4E2D', kind: 'outfit', slot: 'torso' }, kit => {
    const strap = [];
    for (let i = 0; i <= 14; i++) { const t = i / 14, a = -PI * .5 + t * PI * 2; strap.push([Math.sin(a) * 1.08 * (1 - .15 * Math.cos(a)), .62 - t * 1.62 + .1 * Math.sin(t * PI), Math.cos(a) * .6]); }
    rod(kit, strap, .045, LEATHER, { capStart: false, capEnd: false });
    roundBox(kit, { pos: [1.02, -1.15, -.12], rot: [0, PI / 2, 0], len: .26, w: .7, h: .56, rc: .1, steps: 4, shape: t => [1 - .06 * Math.abs(t - .5), 1, 0], cols: [T] });
    knob(kit, [1.02, -1.04, -.26], .05, .035, BRASS, [-PI / 2, 0, 0]);
  });
  // Tabard: a guard's surcoat panel over the chest, a crest boss and pauldrons.
  outfit('Tabard', { smooth: CLOTH, tint: 'B23A48', kind: 'outfit', slot: 'torso' }, kit => {
    sheet(kit, { top: .7, len: 2.45, steps: 9, w: t => 1.25 + .1 * t, th: () => .05, depth: (t, x) => -.56 - .02 * t + .08 * x * x, cols: [T, T, TL, T, T, T, T, T, TD] });
    forward(kit, [0, .1, -.6], P([[0, -.01], [.24, -.01], [.245, .02], [.12, .07], [0, .08]], [0, .02, .03, .06]), { n: 20, color: (l, i, c) => Math.hypot(c[0], c[2]) < .1 ? TL : C.GOLD });
    for (const s of [-1, 1]) kit.group({ pos: [s * 1.3, .62, 0] }, () => lat(kit, P([[0, -.18], [.5, -.18], [.54, -.12], [.5, .14], [.28, .3], [0, .34]], [0, .04, .04, .14, .14]), {
      n: 20, color: (l, i, c) => c[1] > .2 ? BRASS : IRON }));
  });
  // Tool belt: a thick belt with pouches and a buckle (worn at the waist).
  outfit('ToolBelt', { smooth: HARD, tint: '5A4030', kind: 'outfit', slot: 'torso' }, kit => {
    ring(kit, { pos: [0, -.8, 0], R: 1, r: .09, N: 32, sx: 1.04, sz: .55, color: T });
    roundBox(kit, { pos: [0, -.8, -.6], len: .07, w: .3, h: .26, rc: .05, steps: 2, kArc: 3, cols: [BRASS] });
    for (const x of [-.72, .76]) roundBox(kit, { pos: [x, -.98, -.52], len: .2, w: .34, h: .4, rc: .07, steps: 3, cols: [TD] });
  });
  // Scarf: a knitted neck wrap with a tail over the chest.
  outfit('Scarf', { smooth: CLOTH, tint: 'FFD166', kind: 'outfit', slot: 'torso' }, kit => {
    ring(kit, { pos: [0, .78, 0], R: .62, r: .13, N: 28, sx: 1.05, sz: .9, color: T });
    sheet(kit, { top: .72, len: 1.05, w: () => .3, th: () => .05, depth: (t) => -.62 - .04 * t, steps: 5, kW: 3, cols: [T, TL, T, TL, T, T], xoff: t => .32 + .05 * t });
  });

  // =========================================================================
  // Hand props (origin = the grip; the shaft runs down -Y).
  // =========================================================================
  // Smith's hammer: ash handle with a brass ferrule, a banded iron head with domed faces.
  outfit('PropHammer', { smooth: HARD, tint: '4A4A4A', kind: 'outfit', slot: 'hand' }, kit => {
    rod(kit, [[0, .3, 0], [0, -.4, 0], [0, -.98, 0], [0, -1.05, 0], [0, -1.12, 0], [0, -1.2, 0]], i => [.085, .08, .076, .1, .1, .075][i], WOOD, { capEnd: false });
    roundBox(kit, { pos: [0, -1.28, 0], rot: [0, PI / 2, 0], len: .78, w: .34, h: .34, rc: .08, steps: 6, shape: t => [1 - .15 * Math.abs(t - .5), 1 - .15 * Math.abs(t - .5), 0], cols: [IRON, T, T, T, T, T, IRON] });
  });
  // Angler's rod: cork grip, brass reel, a tapered blank with ring guides to a fine tip.
  outfit('PropRod', { smooth: HARD, tint: '8B5A2B', kind: 'outfit', slot: 'hand' }, kit => {
    rod(kit, [[0, -.35, 0], [0, 0, 0], [0, .4, 0]], .075, C.CLOTH, { capEnd: false });
    const blank = [[0, .38, 0], [0, 1.6, -.04], [0, 2.8, -.16], [0, 3.9, -.36]];
    rod(kit, blank, (i, m) => .055 * (1 - .62 * i / (m - 1)), T);
    kit.group({ pos: [.13, .1, 0], rot: [0, 0, PI / 2] }, () => lat(kit, P([[0, -.06], [.12, -.06], [.13, .04], [.1, .06], [0, .07]], [0, .02, .02, .03]), { n: 16, color: (l, i, c) => c[1] > .04 ? IRON : BRASS }));
    for (const [y, z] of [[1.2, -.03], [2.2, -.1], [3.1, -.2]]) knob(kit, [0, y, z - .05], .04, .035, BRASS);
  });
  // Scholar's open tome: two cambered page blocks in a leather cover, a ribbon.
  outfit('PropTome', { smooth: CLOTH, tint: '5B3F8C', kind: 'outfit', slot: 'hand' }, kit => {
    for (const s of [-1, 1]) {
      roundBox(kit, { pos: [s * .3, -.2, -.42], rot: [-.55, s * .2, 0], len: .62, w: .6, h: .1, rc: .045, steps: 4, kW: 4, kH: 1, shape: t => [1, 1 + .35 * Math.sin(PI * t), 0], cols: [PAPER] });
      roundBox(kit, { pos: [s * .31, -.27, -.37], rot: [-.55, s * .2, 0], len: .7, w: .66, h: .07, rc: .034, steps: 2, kW: 4, kH: 1, kArc: 4, cols: [T] });
    }
    rod(kit, [[0, -.43, -.17], [0, -.06, -.66]], .045, TD);
    blade(kit, { pos: [0, -.18, -.5], rot: [-.55 - PI / 2, 0, 0], len: .55, w: .06, th: .015, tip: .8, root: 1, belly: .1, steps: 5, cols: [C.CRIMSON] });
  });
  // Ledger: a closed account book with a banded spine and a brass clasp.
  outfit('PropLedger', { smooth: HARD, tint: '1F2F4F', kind: 'outfit', slot: 'hand' }, kit => {
    roundBox(kit, { pos: [0, -.25, -.2], len: .26, w: .72, h: .95, rc: .05, steps: 4, kW: 3, kH: 4, cols: [T, PAPER, PAPER, PAPER, T] });
    roundBox(kit, { pos: [.33, -.25, -.2], rot: [0, PI / 2, 0], len: .14, w: .32, h: .12, rc: .04, steps: 2, kArc: 3, cols: [BRASS] });
  });
  // Lantern: a brass cage, a glass globe, a cap and a bail handle, a flame inside.
  outfit('PropLantern', { smooth: HARD, tint: 'F9CC77', kind: 'outfit', slot: 'hand' }, kit => {
    const bail = []; for (let i = 0; i <= 12; i++) { const a = PI * i / 12; bail.push([0, -.36 + Math.sin(a) * .26, Math.cos(a) * .17]); }
    rod(kit, bail, .025, IRON, { capStart: false, capEnd: false });
    kit.group({ pos: [0, -.75, 0] }, () => lat(kit, P([[0, -.34], [.27, -.34], [.22, -.27], [.24, 0], [.21, .22], [.17, .27], [.2, .32], [.12, .42], [0, .46]], [0, .04, .04, .1, .04, .03, .04, .1]), {
      n: 24, color: (l, i, c) => c[1] < -.27 ? IRON : c[1] < .21 ? GLASS : BRASS }));
    for (let i = 0; i < 4; i++) { const a = i * PI / 2 + PI / 4; rod(kit, Array.from({ length: 4 }, (_, k) => [Math.cos(a) * .245, -1.07 + k * .18, Math.sin(a) * .245]), .04, BRASS, { capStart: false, capEnd: false }); }
    kit.blob(0, -.76, 0, .1, .15, .1, { sub: 2, color: () => T });
  });
  // Rune staff: a twisted shaft with a gold collar, gold claws holding a glowing crystal.
  outfit('PropStaff', { smooth: HARD, tint: 'C77DFF', kind: 'outfit', slot: 'hand' }, kit => {
    rod(kit, [[0, -1.7, 0], [0, -.6, .02], [0, .6, -.02], [0, 2.4, 0], [0, 2.5, 0], [0, 2.6, 0]], i => [.085, .08, .075, .07, .1, .1][i], WOOD, { capEnd: false,
      color: (l, k, c) => c[1] > 2.45 ? C.GOLD : WOOD });
    for (let i = 0; i < 3; i++) { const a = i * 2 * PI / 3; rod(kit, [[Math.cos(a) * .06, 2.56, Math.sin(a) * .06], [Math.cos(a) * .2, 2.8, Math.sin(a) * .2], [Math.cos(a) * .12, 3.06, Math.sin(a) * .12]], (j, m) => .035 - .012 * j / (m - 1), C.GOLD, { capStart: false }); }
    kit.group({ pos: [0, 2.95, 0] }, () => lat(kit, OK.spindleProfile(.16, -.24, -.04, .3, 5), { n: 16, color: (l, i, c) => c[1] > .05 ? TL : T }));
  });
  // Guard's spear: an ash shaft, a leaf blade, a brass collar, an iron butt cap.
  outfit('PropSpear', { smooth: HARD, tint: 'D8DEE6', kind: 'outfit', slot: 'hand' }, kit => {
    rod(kit, [[0, -1.88, 0], [0, 0, 0], [0, 2.5, 0]], (i) => [.065, .07, .065][i], WOOD, { capStart: false, capEnd: false });
    kit.group({ pos: [0, 2.48, 0] }, () => lat(kit, P([[0, -.05], [.08, -.05], [.1, .05], [.09, .16], [.06, .21], [0, .21]], [0, .02, .03, .03, .02]), { n: 16, color: () => BRASS }));
    blade(kit, { pos: [0, 2.66, 0], len: .9, w: .32, th: .05, tip: .04, root: .3, belly: .35, steps: 9, cols: [T] });
    kit.group({ pos: [0, -1.92, 0] }, () => lat(kit, [...OK.bowl(.08, 0, .07, 3), [.08, 0], [.075, .08], [0, .08]], { n: 16, color: () => IRON }));
  });
  // Sword: a fullered blade, a curved crossguard, a wrapped grip, a pommel.
  outfit('PropSword', { smooth: HARD, tint: 'D8DEE6', kind: 'outfit', slot: 'hand' }, kit => {
    rod(kit, [[0, .3, 0], [0, -.3, 0]], .07, LEATHER, { capStart: false, capEnd: false });
    kit.blob(0, .36, 0, .1, .095, .1, { sub: 2, color: () => C.GOLD });
    rod(kit, [[-.38, -.28, 0], [-.18, -.34, 0], [0, -.36, 0], [.18, -.34, 0], [.38, -.28, 0]], .05, C.GOLD);
    blade(kit, { pos: [0, -.36, 0], rot: [PI, 0, 0], len: 2.1, w: .26, th: .045, tip: .05, root: .95, belly: .12, steps: 10, cols: [T] });
  });
  // Pickaxe: a hickory haft with an iron collar and a curved double-pointed head.
  outfit('PropPickaxe', { smooth: HARD, tint: '5B3F8C', kind: 'outfit', slot: 'hand' }, kit => {
    rod(kit, [[0, .25, 0], [0, -.7, 0], [0, -1.45, 0], [0, -1.52, 0], [0, -1.6, 0]], i => [.08, .076, .072, .11, .11][i], WOOD, { capEnd: false, color: (l, k, c) => c[1] < -1.48 ? IRON : WOOD });
    rod(kit, [[-.78, -1.38, 0], [-.4, -1.58, 0], [0, -1.64, 0], [.4, -1.58, 0], [.78, -1.38, 0]], (i, m) => .1 * (1 - .7 * Math.abs(i - (m - 1) / 2) / ((m - 1) / 2)), T);
  });
  // Bow saw: a wooden frame, a steel blade and a twisted tension cord.
  outfit('PropSaw', { smooth: HARD, tint: 'BFC5CC', kind: 'outfit', slot: 'hand' }, kit => {
    rod(kit, [[0, .2, 0], [0, -.25, 0], [-.1, -.8, 0], [0, -1.4, 0], [.25, -1.6, 0]], i => [.08, .065, .05, .05, .05][i], WOOD);
    blade(kit, { pos: [.05, -.25, -.02], rot: [PI, 0, -.08], len: 1.35, w: .14, th: .025, tip: .8, root: 1, belly: .05, steps: 6, cols: [T] });
    rod(kit, [[0, -.25, .045], [-.04, -.8, .05], [.05, -1.35, .045]], .025, PAPER);
  });
  // Produce crate: a slatted box heaped with fruit (carried on the hip).
  outfit('PropCrate', { smooth: HARD, tint: 'C0392B', kind: 'outfit', slot: 'hand' }, kit => {
    roundBox(kit, { pos: [-.7, -.05, -.6], len: .9, w: 1.2, h: .8, rc: .07, steps: 6, kW: 3, kH: 3, cols: [C.PLANK, C.BARK, C.PLANK, C.PLANK, C.BARK, C.PLANK, C.PLANK] });
    for (const [x, z] of [[-1.0, -.4], [-.7, -.55], [-.4, -.42], [-.85, -.8], [-.52, -.78]])
      kit.blob(x, .42, z, .17, .155, .17, { sub: 2, color: (nrm, mid, _f) => mid[1] > .08 ? TL : T });
  });
  // Scroll: a parchment roll on turned handles with a wax seal.
  outfit('PropScroll', { smooth: HARD, tint: 'C9A227', kind: 'outfit', slot: 'hand' }, kit => {
    kit.group({ pos: [0, -.1, -.15], rot: [0, 0, PI / 2] }, () => lat(kit, P([[0, -.74], [.07, -.72], [.09, -.66], [.07, -.6], [.16, -.57], [.17, 0], [.16, .57], [.07, .6], [.09, .66], [.07, .72], [0, .74]], [0, .03, .03, .03, .03, 0, .03, .03, .03, .03]), {
      n: 20, color: (l, i, c) => Math.abs(c[1]) > .58 ? WOOD : PAPER }));
    forward(kit, [0, -.1, -.31], P([[0, 0], [.1, 0], [.1, .02], [.06, .04], [0, .045]], [0, .01, .02, .02]), { n: 16, color: () => T });
  });
  // Herald's horn: a curved brass horn flaring to a rolled bell, a dyed cord band.
  outfit('PropHorn', { smooth: HARD, tint: 'FFD166', kind: 'outfit', slot: 'hand' }, kit => {
    const pts = []; for (let i = 0; i <= 8; i++) { const t = i / 8; pts.push([0, -.1 - .25 * Math.sin(t * PI), -.1 - t * 1.0]); }
    kit.tube(pts, i => .04 + .1 * (i / 8) ** 2.2, { n: 16, color: (l) => l === 4 ? T : C.GOLD, capStart: true, capEnd: false });
    forward(kit, [0, -.1, -1.1], P([[.135, 0], [.24, .1], [.31, .155], [.28, .19], [.2, .15], [.12, .05]], [0, .08, .035, .035, .06]), { n: 24, color: () => C.GOLD });
  });
  // Fire poker: an iron rod with a ring grip and a hooked, ember-hot tip (Beaconkeeper).
  outfit('PropPoker', { smooth: HARD, tint: 'FF8A3D', kind: 'outfit', slot: 'hand' }, kit => {
    ring(kit, { pos: [0, .3, 0], rot: [0, 0, PI / 2], R: .13, r: .035, N: 28, color: IRON });
    rod(kit, [[0, .2, 0], [0, -1.6, 0], [0, -1.95, -.04], [0, -2.12, -.16], [0, -2.1, -.3]], (i, m) => i < 2 ? .045 : .045 - .012 * (i - 1) / (m - 2), IRON, { capStart: false,
      color: (l, k, c) => c[1] < -1.9 ? T : IRON });
  });
  // Shepherd's crook: a long staff curling into a hook.
  outfit('PropCrook', { smooth: HARD, tint: '8B5A2B', kind: 'outfit', slot: 'hand' }, kit => {
    const pts = [[0, -1.8, 0], [0, 0, 0], [0, 2.3, 0]];
    for (let i = 1; i <= 7; i++) { const a = i / 7 * PI * 1.15; pts.push([0, 2.3 + Math.sin(a) * .28, -(1 - Math.cos(a)) * .28]); }
    kit.tube(pts, .07, { n: 16, color: T });
  });
  // Hoe: a long haft with an angled iron blade.
  outfit('PropHoe', { smooth: HARD, tint: '8D6E63', kind: 'outfit', slot: 'hand' }, kit => {
    rod(kit, [[0, .3, 0], [0, -1.0, 0], [0, -2.3, 0]], .065, WOOD, { capEnd: false });
    blade(kit, { pos: [0, -2.28, 0], rot: [-PI / 2 - .3, 0, 0], len: .5, w: .44, th: .035, tip: .85, root: .95, belly: .15, steps: 5, cols: [IRON, T] });
  });

  return {};
};
