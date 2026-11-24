// Creatures (docs/DEPTH-CONTRACT.md §48): every monster, slayer / lair / raid /
// world boss, dungeon guardian, Siege creature and pet companion is drawn by
// creatures.client.lua from forged meshes authored here, never from blocks.
// Loaded by art/generate-props.cjs; output goes to art/CreatureCatalog.lua
// (ReplicatedStorage.AetherCreatureArt, its own download) plus one OBJ each.
//
// Frame ("rig space"): studs at creature scale 1, +Y up, the face looks down
// -Z, the origin is the combat Root's centre and the ground is y = -hip (the
// blueprint hip in combat.server.lua). Bosses scale the whole rig uniformly by
// CreatureScale (2.2 slayer / lair / raid, 3.2 world).
//
// A rig is one core mesh (body + head, tinted with the creature's colour) plus
// limb segments that the client poses every frame: legs swing about their hip
// pivot, wings flap about their root, tails sway, shards orbit. Limb shapes are
// shared between kinds and sized per rig by `k` (a number or [x,y,z]). Mirrored
// limbs reuse one mesh: mirror 'roll' turns it 180 degrees about Z (flat wings
// and fins, symmetric about their own plane), 'yaw' 180 degrees about Y (arms
// and claws that are symmetric front to back).
//
// Every surface is a smooth-shaded lathe, loft, tube or subdivided ellipsoid
// (crease 42-50 degrees, >= 10 segments): no boxes, prisms or facets. Dark sockets mark the
// eyes; the client seats small Neon glow balls in them (glow list), so eyes,
// cores and rune seams bloom. Region palettes come from the tint (the
// creature's AetherData colour): backs take the dark tint, bellies the light
// one, horns / claws / bone and glass stay fixed.
'use strict';
module.exports = ({ creature, C, PI, hash }) => {
  const { TINT: T, TINT_DARK: TD, TINT_LIGHT: TL } = C;
  const rigs = {};
  // Smoothing creases. Every ring, tube and loft in this file has >= 10
  // segments (36 degrees), so 360 / n stays under every crease below: no
  // surface reads as faceted (QC H4; verify-mesh measures the hard edges).
  const ORG = 50, HARD = 42, GLASS = 44;

  // -------------------------------------------------------------------------
  // Helpers. Only smooth primitives are used here: lathes, tubes, lofts and
  // subdivided ellipsoids (no boxes, prisms, jewels or square-section rings).
  // Colour is chosen only by ring band (level / section index along a form) or
  // by height (the face centre), never by the facet index around a form.
  // -------------------------------------------------------------------------
  // Lathe laid along -Z (profile t grows toward the nose). sx widens, sz raises.
  const along = (kit, pos, profile, opts, pitch = 0, yaw = 0) =>
    kit.group({ pos, rot: [-PI / 2 + pitch, yaw, 0] }, () => kit.lathe(profile, opts));
  // Height gradient for a lathe laid along Z (its local +Z is world up): the
  // back takes `top`, the flanks `side`, the belly `belly`; bands add a ring
  // band override (e.g. a collar) by level.
  const dorsal = (top = TD, side = T, belly = TL, bands = {}) => (level, i, p) => {
    if (bands[level] !== undefined) return bands[level];
    const r = Math.hypot(p[0], p[2]) || 1, s = p[2] / r;
    return s > .42 ? top : s < -.5 ? belly : side;
  };
  // Ring bands for upright lathes and tubes: colour by level / ring index.
  const bands = (...cols) => level => cols[Math.max(0, Math.min(cols.length - 1, level))];
  // Countershaded ellipsoid by face-centre height.
  const ell = (kit, x, y, z, rx, ry, rz, col = [TD, T, TL], sub = 2, extra = {}) =>
    kit.blob(x, y, z, rx, ry, rz, { sub, ...extra,
      color: Array.isArray(col) ? (n, m) => m[1] > ry * .42 ? col[0] : m[1] < -ry * .38 ? col[2] : col[1] : () => col });
  // Tapered horn / claw / tooth along a polyline (n >= 10 around).
  const horn = (kit, pts, r, color = C.HORN, n = 10) => {
    const m = pts.length;
    kit.tube(pts, i => Math.max(.018, r * (1 - i / (m - 1)) ** .85), { n, color });
  };
  // Smooth bipyramid gem / rivet head (n = 10).
  const gem = (kit, x, y, z, r, h, color, rot = [0, 0, 0]) =>
    kit.group({ pos: [x, y, z], rot }, () => kit.lathe([[0, -h], [r, 0], [0, h]], { n: 10, color }));
  // Domed rivet facing local -Z of `rot`.
  const rivet = (kit, x, y, z, r, color, yaw = 0, pitch = 0) =>
    kit.group({ pos: [x, y, z], rot: [-PI / 2 + pitch, yaw, 0] }, () => kit.lathe([[r, 0], [r * .72, r * .42], [0, r * .6]], { n: 10, color, capStart: true }));
  // Eye: a dark socket and a domed glassy iris; the client adds the Neon glow.
  const eye = (kit, x, y, z, r, iris = C.GLINT) => {
    ell(kit, x, y, z, r * 1.25, r, r * .9, C.SOCKET, 1);
    along(kit, [x, y, z - r * .5], [[r * .62, 0], [r * .45, r * .26], [0, r * .37]], { n: 10, color: iris, capStart: true });
  };
  const eyes = (kit, x, y, z, r, iris) => { eye(kit, -x, y, z, r, iris); eye(kit, x, y, z, r, iris) };
  const glowEyes = (x, y, z, r, color) => [{ kind: 'eye', at: [-x, y, z - r * .55], r: r * .62, color }, { kind: 'eye', at: [x, y, z - r * .55], r: r * .62, color }];
  // Lofted, cambered blade with real thickness (fins, petals, feathers, crown
  // spikes, swords): the span runs along local +Y from `pos`, the chord along
  // X, the (lens) thickness along Z. `cols` colours by section from the root.
  const blade = (kit, { pos = [0, 0, 0], rot = [0, 0, 0], len = 1, w = .4, th = .06, tip = .04, steps = 4, m = 10, belly = .3,
    sweep = 0, camber = 0, cols = [T] }) =>
    kit.group({ pos, rot }, () => kit.group({ rot: [-PI / 2, 0, 0] }, () => kit.loft(
      Array.from({ length: steps + 1 }, (_, s) => {
        const t = s / steps;
        const prof = t < belly ? .5 + .5 * Math.sin(t / belly * PI / 2) : 1 - (1 - tip) * ((t - belly) / (1 - belly)) ** 1.25;
        const wt = Math.max(w * prof, .014), tt = Math.max(th * Math.sqrt(prof), .007);
        const ox = sweep * t * t, oy = camber * Math.sin(PI * t);
        return { z: t * len, points: Array.from({ length: m }, (_, k) => { const a = k * 2 * PI / m; return [ox + Math.cos(a) * wt / 2, oy + Math.sin(a) * tt] }) };
      }), { color: s => cols[Math.max(0, Math.min(cols.length - 1, Math.floor(s * cols.length / (steps + 1))))] })));
  // A ridge of cambered plates / spines along the back (x = 0), leaning back.
  const spines = (kit, list, color = TL, th = .07) => {
    for (const [y, z, h, l, lean] of list)
      blade(kit, { pos: [0, y, z], rot: [lean ?? -.45, 0, 0], len: h, w: l, th, tip: .05, belly: .35, cols: [color] });
  };
  // Flat wing / membrane lofted along +X (span 0..1): chord from lead(t) to
  // trail(t) along Z, lens thickness th(t) symmetric about y = 0 (so a roll
  // mirror reuses it). `cols` colours by span section.
  const membrane = (kit, { lead, trail, th = () => .03, steps = 10, m = 10, cols = [T], x0 = 0, x1 = 1 }) =>
    kit.group({ rot: [0, PI / 2, 0] }, () => kit.loft(
      Array.from({ length: steps + 1 }, (_, s) => {
        const t = s / steps, z0 = lead(t), z1 = trail(t), c = (z0 + z1) / 2, h = Math.max((z1 - z0) / 2, .012), tt = Math.max(th(t), .006);
        return { z: x0 + (x1 - x0) * t, points: Array.from({ length: m }, (_, k) => { const a = k * 2 * PI / m; return [-(c + Math.cos(a) * h), Math.sin(a) * tt] }) };
      }), { color: s => cols[Math.max(0, Math.min(cols.length - 1, Math.floor(s * cols.length / (steps + 1))))] }));
  // Torus (halos, rings): a lathe of a circle, n around, m around the tube.
  const torus = (kit, { pos = [0, 0, 0], rot = [0, 0, 0], R = 1, r = .05, n = 36, m = 8, flat = 1, color = T }) =>
    kit.group({ pos, rot }, () => kit.lathe(Array.from({ length: m + 1 }, (_, b) => { const a = b * 2 * PI / m; return [R + r * Math.cos(a), r * Math.sin(a) * flat] }), { n, color }));
  // Lofted rounded box (helms, sabatons, plates): sections along local +Z,
  // superellipse cross-sections w x h; `shape(t)` scales [w, h, yOffset].
  const roundBox = (kit, { pos = [0, 0, 0], rot = [0, 0, 0], len = 1, w = 1, h = 1, steps = 6, m = 16, ex = 2.6, shape = () => [1, 1, 0], cols = [T], capEnd = true }) =>
    kit.group({ pos, rot }, () => kit.loft(
      Array.from({ length: steps + 1 }, (_, s) => {
        const t = s / steps, [sw, sh, oy] = shape(t);
        return { z: t * len - len / 2, points: Array.from({ length: m }, (_, k) => {
          const a = k * 2 * PI / m, c = Math.cos(a), sn = Math.sin(a);
          return [Math.sign(c) * Math.abs(c) ** (2 / ex) * w * sw / 2, oy + Math.sign(sn) * Math.abs(sn) ** (2 / ex) * h * sh / 2];
        }) };
      }), { capEnd, color: s => cols[Math.max(0, Math.min(cols.length - 1, Math.floor(s * cols.length / (steps + 1))))] }));
  const rig = (kind, spec) => { rigs[kind] = spec; };

  // Hoofed leg: muscled thigh, knee collar, slim cannon, fetlock tuft, hoof.
  creature('HoofLeg', { smooth: ORG, tint: 'A0683D', kind: 'limb' }, kit => {
    kit.tube([[0, .05, 0], [0, -.12, .03], [0, -.28, .04], [0, -.42, .02], [0, -.55, -.01], [0, -.68, -.03], [0, -.8, 0]], [.26, .25, .2, .15, .115, .1, .095], { n: 12, color: bands(TD, TD, T, T, T, T) });
    kit.lathe([[.15, -.47], [.165, -.43], [.16, -.39], [.14, -.36]], { n: 12, color: TL });
    ell(kit, 0, -.78, .02, .14, .08, .15, [T, TL, TL], 1);
    kit.lathe([[.135, -1], [.142, -.96], [.135, -.9], [.11, -.85], [.09, -.82]], { n: 12, capStart: true, capEnd: true, color: bands(C.CLAW, C.HORN, C.HORN, C.HORN), capColor: C.CLAW });
  });
  // Paw leg (digitigrade): thigh, hock bend, padded paw with three toes and claws.
  creature('PawLeg', { smooth: ORG, tint: '8A6A4A', kind: 'limb' }, kit => {
    kit.tube([[0, .05, 0], [0, -.12, -.05], [0, -.28, -.07], [0, -.45, .03], [0, -.62, .08], [0, -.78, .08], [0, -.9, .02]], [.23, .22, .18, .13, .1, .092, .088], { n: 12, color: bands(TD, TD, T, T, T, T) });
    ell(kit, 0, -.93, -.06, .135, .075, .17, [T, T, TL], 1);
    for (const x of [-.075, 0, .075]) {
      ell(kit, x, -.95, -.2, .05, .045, .055, TL, 1);
      horn(kit, [[x, -.95, -.24], [x, -.97, -.29], [x, -.995, -.31]], .026, C.CLAW);
    }
  });
  // Clawed leg (reptile / hound): scaled thigh, armoured shin collars, splayed claws, a spur.
  creature('ClawLeg', { smooth: ORG, tint: '5E7C68', kind: 'limb' }, kit => {
    kit.tube([[0, .06, 0], [0, -.1, -.08], [0, -.25, -.12], [0, -.42, -.06], [0, -.6, .03], [0, -.76, .05], [0, -.9, 0]], [.27, .25, .21, .15, .125, .11, .1], { n: 12, color: bands(TD, TD, T, T, T, T) });
    for (const [y, z, r] of [[-.47, -.08, .15], [-.63, .0, .135]]) kit.group({ pos: [0, y, z], rot: [.2, 0, 0] }, () => kit.lathe([[r * .9, -.05], [r, -.02], [r, .02], [r * .85, .05]], { n: 12, color: TL }));
    ell(kit, 0, -.93, -.06, .15, .07, .18, [TD, T, T], 1);
    for (const a of [-.45, 0, .45]) kit.group({ pos: [Math.sin(a) * .1, -.95, -.18], rot: [0, a, 0] }, () => horn(kit, [[0, 0, 0], [0, -.015, -.08], [0, -.04, -.15], [0, -.055, -.19]], .04, C.CLAW));
    horn(kit, [[0, -.5, .12], [0, -.45, .22], [0, -.36, .29]], .045, C.HORN);
  });
  // Arthropod leg: coxa out along +X, femur up and out, tibia down to a claw,
  // with ring collars at every joint (n = 12) and two bristle spines.
  creature('ChitinLeg', { smooth: ORG, tint: '6B5240', kind: 'limb' }, kit => {
    kit.tube([[0, 0, 0], [.14, .06, 0], [.3, .16, 0], [.46, .27, 0], [.62, .32, 0]], [.115, .105, .095, .085, .08], { n: 12, color: bands(TD, T, T, T) });
    kit.tube([[.66, .31, 0], [.76, .17, 0], [.85, -.05, 0], [.91, -.28, 0], [.95, -.5, 0], [.96, -.62, 0]], [.078, .072, .062, .052, .04, .032], { n: 12, color: bands(T, T, TL, TL, TL) });
    for (const [x, y, r, rz] of [[.02, .01, .13, -.4], [.64, .32, .1, .3], [.92, -.33, .06, .1]])
      kit.group({ pos: [x, y, 0], rot: [0, 0, rz - PI / 2] }, () => kit.lathe([[r * .9, -.03], [r, -.012], [r, .012], [r * .9, .03]], { n: 12, color: TD }));
    horn(kit, [[.96, -.6, 0], [.965, -.7, 0], [.955, -.79, 0], [.94, -.86, 0]], .034, C.CLAW);
    for (const t of [.25, .6]) horn(kit, [[.7 + t * .25, .25 - t * .8, 0], [.76 + t * .25, .27 - t * .8, 0], [.82 + t * .25, .31 - t * .8, 0]], .02, C.HORN);
  });
  // Spider leg: tall knee arch, banded segments with joint collars, hooked tip.
  creature('SpiderLeg', { smooth: ORG, tint: '3F3550', kind: 'limb' }, kit => {
    kit.tube([[0, 0, 0], [.12, .12, 0], [.25, .26, 0], [.4, .41, 0], [.55, .48, 0]], [.1, .095, .085, .075, .07], { n: 12, color: bands(T, T, TL, T) });
    ell(kit, .58, .48, 0, .085, .085, .085, TD, 1);
    kit.tube([[.6, .47, 0], [.68, .33, 0], [.76, .14, 0], [.84, -.07, 0], [.91, -.28, 0], [.96, -.46, 0], [.98, -.6, 0]], [.068, .064, .058, .05, .042, .032, .026], { n: 12, color: bands(TD, TD, TL, TD, TD, TL) });
    for (const [x, y, r, rz] of [[.25, .26, .095, -.8], [.76, .14, .065, .35], [.91, -.28, .05, .3]])
      kit.group({ pos: [x, y, 0], rot: [0, 0, rz - PI / 2] }, () => kit.lathe([[r * .9, -.025], [r, -.01], [r, .01], [r * .9, .025]], { n: 12, color: TL }));
    horn(kit, [[.98, -.58, 0], [.99, -.7, 0], [.975, -.8, 0], [.95, -.86, 0]], .028, C.CLAW);
  });
  // Root leg (plants): a twisting, knotted root that splits into rootlets.
  creature('RootLeg', { smooth: ORG, tint: '5B4636', kind: 'limb' }, kit => {
    kit.tube([[0, 0, 0], [.09, -.1, .03], [.18, -.2, .05], [.3, -.34, .0], [.4, -.48, -.04], [.48, -.64, -.01], [.55, -.8, .02], [.6, -.97, 0]], [.16, .15, .135, .12, .1, .085, .07, .05],
      { n: 12, color: bands(C.BARK_DARK, C.BARK, C.BARK, C.BARK_DARK, C.BARK, C.BARK, C.BARK_DARK), jitter: (i, k) => 1 + (hash(i, k, 71) - .5) * .18 });
    for (const a of [-.6, .6]) kit.group({ pos: [.5, -.72, 0], rot: [0, a, -.4] }, () => horn(kit, [[0, 0, 0], [.05, -.08, 0], [.09, -.18, 0], [.12, -.27, 0]], .045, C.BARK_DARK));
    for (const [x, y, z, a] of [[.15, -.17, .1, .7], [.38, -.44, -.08, -.6]]) blade(kit, { pos: [x, y, z], rot: [0, a, -.9], len: .2, w: .1, th: .015, cols: [C.LEAF_DARK, C.LEAF] });
  });
  // Vine arm (thornling): a coiling vine with thorns and a cambered leaf tip.
  creature('VineArm', { smooth: ORG, tint: '6BAF5A', kind: 'limb' }, kit => {
    kit.tube([[0, 0, 0], [.04, -.12, -.03], [.05, -.25, -.07], [.03, -.4, -.11], [.05, -.55, -.1], [.08, -.7, -.07], [.05, -.82, -.03], [.02, -.9, 0]], [.1, .095, .088, .078, .068, .056, .045, .035], { n: 12, color: bands(TD, TD, T) });
    for (const t of [.2, .4, .6, .78]) horn(kit, [[.05, -t * 1.05, -.06], [.11, -t * 1.05 + .02, -.1], [.16, -t * 1.05 + .04, -.12], [.2, -t * 1.05 + .06, -.13]], .03, C.BONE);
    blade(kit, { pos: [.02, -.9, 0], rot: [0, 0, PI], len: .38, w: .22, th: .025, camber: .04, cols: [T, TL] });
  });
  // Bushy tail (fur): fluffy tapered lathe with tufted bands and a pale tip.
  creature('FurTail', { smooth: ORG, tint: 'C98D4F', kind: 'limb' }, kit => {
    kit.group({ rot: [PI / 2 - .35, 0, 0] }, () => kit.lathe([[.06, 0], [.12, .08], [.17, .18], [.21, .3], [.22, .42], [.215, .55], [.2, .68], [.16, .8], [.11, .9], [.05, .97], [0, 1]], {
      n: 16, color: bands(TD, T, T, T, T, T, T, C.FUR, C.FUR, C.FUR), jitter: (l, i) => l > 1 && l < 9 ? 1 + Math.sin(i * 2.3 + l * 1.7) * .07 : 1 }));
  });
  // Scaled tail: segmented, tapering, with a cambered spine row and a barb.
  creature('ScaleTail', { smooth: ORG, tint: '5E7C68', kind: 'limb' }, kit => {
    kit.group({ rot: [PI / 2, 0, 0] }, () => kit.lathe([[.2, 0], [.205, .08], [.195, .16], [.18, .26], [.165, .36], [.145, .46], [.125, .56], [.1, .67], [.075, .78], [.05, .88], [.03, .95], [0, 1]], {
      n: 16, sx: 1, sz: .9, color: (l, i, p) => { const s = p[2] / (Math.hypot(p[0], p[2]) || 1); return s < -.45 ? TD : s > .5 ? TL : T } }));
    for (let s = 0; s < 5; s++) blade(kit, { pos: [0, (.19 - s * .03) * .85, .1 + s * .17], rot: [-.9, 0, 0], len: .12 - s * .012, w: .09, th: .02, cols: [C.HORN] });
    kit.group({ pos: [0, 0, .98], rot: [PI / 2, 0, 0] }, () => kit.lathe([[.05, 0], [.085, .05], [.08, .1], [.04, .18], [0, .24]], { n: 12, sx: .45, color: C.HORN, capStart: true }));
  });
  // Fish tail: tapering body section and a forked, cambered fluke.
  creature('FishTail', { smooth: ORG, tint: '4F8FBF', kind: 'limb' }, kit => {
    kit.group({ rot: [PI / 2, 0, 0] }, () => kit.lathe([[.42, 0], [.41, .1], [.38, .2], [.33, .32], [.26, .45], [.19, .57], [.13, .67], [.1, .74], [.09, .78]], {
      n: 16, sz: 1.15, capEnd: true, color: (l, i, p) => { const s = p[2] / (Math.hypot(p[0], p[2]) || 1); return s < -.4 ? TD : s > .5 ? TL : T } }));
    for (const s of [-1, 1]) blade(kit, { pos: [0, s * .04, .72], rot: [s > 0 ? -.85 : -(PI - .85), PI / 2, 0], len: .62, w: .34, th: .035, belly: .45, sweep: .12, cols: [T, TL, TL] });
    blade(kit, { pos: [0, .3, .2], rot: [-.7, PI / 2, 0], len: .32, w: .28, th: .03, cols: [TL] });
  });
  // Feather wing: arm bone, lofted covert membrane and seven cambered primaries.
  creature('FeatherWing', { smooth: ORG, tint: '7B8CDE', kind: 'limb' }, kit => {
    kit.tube([[0, 0, -.12], [.15, 0, -.18], [.32, 0, -.2], [.5, 0, -.17], [.7, 0, -.1], [.92, 0, .02]], [.07, .066, .058, .048, .036, .022], { n: 12, color: TD });
    membrane(kit, { lead: t => -.2 + t * .1, trail: t => .22 - t * .12, th: t => .035 * (1 - t * .6), x1: .82, cols: [TD, T, T, TL] });
    for (let f = 0; f < 7; f++) {
      const x = .3 + f * .095, l = .32 + f * .05 - (f > 4 ? (f - 4) * .1 : 0);
      blade(kit, { pos: [x, 0, -.04], rot: [PI / 2, -.18 - f * .06, 0], len: l, w: .1, th: .018, tip: .25, belly: .2, cols: [T, f > 3 ? TL : T] });
    }
  });
  // Glass wing (sprites): two veined crystal lobes on a root knuckle.
  creature('GlassWing', { smooth: GLASS, tint: 'A8DADC', kind: 'limb' }, kit => {
    ell(kit, .04, 0, 0, .07, .07, .07, TL, 1);
    membrane(kit, { lead: t => -.05 - Math.sin(t * PI) * .38, trail: t => .0 + Math.sin(t * PI * .9) * .05, th: t => .022 * (1 - t * .5), cols: [TL, C.ICE, C.ICE] });
    membrane(kit, { lead: t => .02, trail: t => .06 + Math.sin(t * PI) * .36, th: t => .02, x1: .6, cols: [TL, C.ICE] });
    for (const [a, l] of [[-.32, .85], [-.12, .7], [.35, .5]]) kit.group({ rot: [0, a, 0] }, () => kit.tube([[0, 0, 0], [l * .35, 0, 0], [l * .7, 0, 0], [l, 0, 0]], [.018, .016, .013, .01], { n: 10, color: TL }));
  });
  // Drake wing: arm and three finger bones (n = 12), a scalloped membrane
  // between them (lofted, thin at the trailing edge), a thumb claw.
  creature('DrakeWing', { smooth: ORG, tint: '8E7CF0', kind: 'limb' }, kit => {
    kit.tube([[0, 0, 0], [.12, .03, -.04], [.25, .05, -.07], [.38, .06, -.09], [.46, .06, -.1]], [.1, .092, .082, .074, .07], { n: 12, color: TD });
    ell(kit, .46, .06, -.1, .07, .07, .07, TD, 1);
    horn(kit, [[.47, .08, -.12], [.5, .14, -.17], [.52, .19, -.21], [.52, .22, -.24]], .045, C.CLAW);
    const tips = [[1, .02, .05], [.84, .02, .42], [.6, .02, .7]];
    for (const tip of tips) {
      const mid = [(.46 + tip[0]) / 2, .045, (tip[2] - .1) / 2];
      kit.tube([[.46, .05, -.1], mid, [(mid[0] + tip[0]) / 2, .035, (mid[2] + tip[2]) / 2], tip], [.05, .04, .03, .018], { n: 10, color: TD });
    }
    // Membrane: leading edge along the arm and first finger, trailing edge
    // scalloped between the finger tips.
    membrane(kit, { lead: t => t < .46 ? -.04 - t * .12 : -.1 + (t - .46) / .54 * .15, trail: t => .3 + .4 * Math.sin(t * PI * .75) * (1 - t * .7) - .12 * Math.abs(Math.sin(t * PI * 3)),
      th: t => .028 * (1 - t * .5), steps: 14, x1: .98, cols: [TD, T, T, T, TL] });
  });
  // Ray fin: broad cambered pectoral wing (span along +X), pale underside rim.
  creature('RayFin', { smooth: ORG, tint: '8FB8D6', kind: 'limb' }, kit => {
    membrane(kit, { lead: t => -.62 + t * .55 + t * t * .1, trail: t => .62 - t * .2 - t * t * .3, th: t => .12 * (1 - t) ** .7 + .01, steps: 12, m: 12, cols: [TD, T, T, T, TL] });
  });
  // Jelly tendril: a frilled ribbon hanging down -Y (n = 10, ringed bands).
  creature('JellyTendril', { smooth: ORG, tint: 'B39DDB', kind: 'limb' }, kit => {
    const pts = [], radii = [];
    for (let s = 0; s <= 10; s++) { pts.push([Math.sin(s * .7) * .06, -s / 10, Math.cos(s * .7) * .05 - .05]); radii.push(.075 - s * .0055) }
    kit.tube(pts, radii, { n: 10, color: bands(TL, T, T, TL, T, T, TL, T, T, TL), jitter: (i, k) => 1 + Math.sin(k * PI / 2.5 + i) * .12 });
    for (let s = 2; s < 10; s += 3) gem(kit, pts[s][0], pts[s][1], pts[s][2] - .07, .03, .05, C.GLINT, [PI / 2, 0, 0]);
  });
  // Wisp shard: a smooth bipyramid crystal (orbiting) with a ringed collar.
  creature('WispShard', { smooth: GLASS, tint: '9583B9', kind: 'limb' }, kit => {
    kit.lathe([[0, -.5], [.09, -.38], [.16, -.2], [.2, .0], [.19, .12], [.14, .3], [.07, .45], [0, .55]], { n: 12, color: bands(TD, TD, T, T, TL, TL, TL), jitter: (l, i) => l > 0 && l < 7 ? 1 + Math.sin(i * 1.9 + l) * .06 : 1 });
    kit.lathe([[.205, -.06], [.225, -.02], [.225, .02], [.205, .06]], { n: 12, color: C.GOLD });
  });
  // Crystal shard (sentinel / seer / sovereign orbit): long bipyramid in a brass collar.
  creature('CrystalShard', { smooth: GLASS, tint: 'BFE4FF', kind: 'limb' }, kit => {
    kit.lathe([[0, -.5], [.08, -.38], [.14, -.2], [.18, .0], [.17, .12], [.13, .28], [.07, .42], [0, .5]], { n: 12, color: bands(TD, TD, T, T, TL, TL, TL) });
    kit.lathe([[.185, -.07], [.21, -.03], [.21, .03], [.185, .07]], { n: 12, color: C.BRASS });
  });
  // Wraith arm: a folded sleeve with a tattered hem and torn strips, a clawed hand.
  creature('WraithArm', { smooth: ORG, tint: '7FD6C8', kind: 'limb' }, kit => {
    kit.lathe([[.14, 0], [.16, -.1], [.19, -.22], [.22, -.36], [.25, -.5], [.29, -.62], [.31, -.7], [.28, -.74]], { n: 16, color: bands(TD, TD, T, T, T, TL, TL),
      jitter: (l, i) => 1 + Math.sin(i * PI / 2) * .06 * (l > 1 ? 1 : 0) + (l >= 6 ? (hash(l, i, 53) - .5) * .3 : 0), lift: (l, i) => l === 7 ? (hash(l, i, 54) - .5) * .14 : 0 });
    for (const [a, l] of [[.4, .3], [2.2, .38], [4.0, .26]]) blade(kit, { pos: [Math.cos(a) * .27, -.7, Math.sin(a) * .27], rot: [PI, a, 0], len: l, w: .1, th: .012, tip: .3, cols: [TL] });
    ell(kit, 0, -.62, -.04, .1, .12, .1, C.VOID, 1);
    for (const a of [-.5, 0, .5]) kit.group({ pos: [Math.sin(a) * .07, -.72, -.08], rot: [.2, a, 0] }, () => horn(kit, [[0, 0, 0], [0, -.08, -.02], [0, -.15, -.06], [0, -.22, -.12]], .028, C.ICE));
  });
  // Golem arm (metal): riveted, trim-banded pauldron dome, upper arm, piston,
  // elbow, gauntlet with a raised trim band, segmented curled fingers.
  creature('GolemArm', { smooth: HARD, tint: 'D4A84B', kind: 'limb' }, kit => {
    kit.lathe([[.31, -.06], [.36, -.02], [.37, .05], [.36, .12], [.32, .2], [.24, .27], [.13, .31], [0, .33]], { n: 16, color: bands(C.BRASS, C.BRASS, TD, T, T, T, TL), capStart: true });
    for (let i = 0; i < 6; i++) { const a = i * PI / 3; rivet(kit, Math.cos(a) * .355, .06, Math.sin(a) * .355, .035, C.BRASS, PI / 2 - a + PI, 0) }
    kit.lathe([[.19, -.5], [.22, -.44], [.23, -.3], [.22, -.15], [.2, -.06]], { n: 12, color: bands(T, T, TD, T), capStart: true, capEnd: true });
    kit.tube([[.12, -.12, .16], [.12, -.3, .17], [.12, -.48, .15]], [.04, .04, .04], { n: 12, color: C.IRON });
    ell(kit, 0, -.55, 0, .17, .14, .17, C.IRON, 1);
    kit.lathe([[.18, -.84], [.24, -.8], [.265, -.74], [.27, -.68], [.27, -.64], [.25, -.6], [.2, -.57]], { n: 14, color: bands(TD, C.BRASS, C.BRASS, T, T, T), capStart: true, capEnd: true });
    ell(kit, 0, -.92, -.02, .2, .13, .19, [T, TD, TD], 2);
    for (const x of [-.13, -.045, .045, .13]) kit.tube([[x, -.94, -.14], [x, -.99, -.22], [x, -1.07, -.22], [x, -1.11, -.15]], [.048, .045, .042, .038], { n: 10, color: bands(TD, C.IRON, TD) });
    kit.tube([[.2, -.9, -.08], [.25, -.97, -.15], [.22, -1.04, -.2]], [.05, .045, .04], { n: 10, color: TD });
  });
  // Golem leg (metal): thigh, twin pistons (n = 12), knee cop, shin, lofted sabaton.
  creature('GolemLeg', { smooth: HARD, tint: 'D4A84B', kind: 'limb' }, kit => {
    kit.lathe([[.25, -.42], [.29, -.36], [.3, -.2], [.29, -.06], [.26, .02]], { n: 14, color: bands(T, T, TD, T), capStart: true, capEnd: true });
    for (const x of [-.17, .17]) kit.tube([[x, -.08, .2], [x, -.3, .22], [x, -.52, .2]], [.045, .045, .045], { n: 12, color: C.IRON });
    ell(kit, 0, -.48, -.06, .2, .17, .2, C.IRON, 2);
    kit.group({ pos: [0, -.46, -.2], rot: [-PI / 2 + .25, 0, 0] }, () => kit.lathe([[.17, -.06], [.19, 0], [.17, .07], [.1, .11], [0, .12]], { n: 14, sz: .7, color: bands(C.BRASS, C.BRASS, T, T), capStart: true }));
    kit.lathe([[.2, -.86], [.23, -.78], [.24, -.66], [.22, -.56], [.2, -.5]], { n: 14, color: bands(TD, TD, T, T), capEnd: true });
    roundBox(kit, { pos: [0, -.93, -.08], len: .7, w: .5, h: .15, steps: 6, shape: t => [.82 + .18 * Math.sin(t * PI * .8), 1 - Math.max(0, t - .6) * .9, -Math.max(0, t - .6) * .02], cols: [TD, T, T, C.BRASS], capEnd: true });
  });
  // Stone arm (marble / crag): carved deltoid, banded biceps, inset rune groove,
  // bronze bracer, sculpted fist with knuckles.
  creature('StoneArm', { smooth: ORG, tint: '5FA8D3', kind: 'limb' }, kit => {
    ell(kit, 0, .02, 0, .34, .3, .32, [TL, T, TD], 2, { seed: 7, amount: .05 });
    kit.lathe([[.2, -.55], [.22, -.48], [.235, -.36], [.24, -.22], [.225, -.1], [.2, 0]], { n: 14, color: bands(T, T, T, T, T), capStart: true, jitter: (l, i) => 1 + Math.sin(i * .9 + l) * .04 });
    kit.lathe([[.243, -.31], [.247, -.29], [.247, -.25], [.243, -.23]], { n: 14, color: C.RUNE });
    kit.lathe([[.22, -.64], [.255, -.61], [.258, -.56], [.255, -.51], [.22, -.48]], { n: 14, color: bands(C.BRASS, C.GOLD, C.GOLD, C.BRASS) });
    kit.lathe([[.2, -.84], [.225, -.76], [.23, -.68], [.21, -.6]], { n: 14, color: TL });
    ell(kit, 0, -.94, -.02, .23, .2, .22, [T, TD, TD], 2, { seed: 9, amount: .05 });
    for (const x of [-.12, 0, .12]) ell(kit, x, -.96, -.2, .065, .06, .06, TD, 1);
  });
  // Stone leg: tapered column with a rune groove, kneecap, shin, round plinth foot.
  creature('StoneLeg', { smooth: ORG, tint: '5FA8D3', kind: 'limb' }, kit => {
    kit.lathe([[.24, -.5], [.27, -.42], [.29, -.3], [.3, -.18], [.29, -.06], [.26, .02]], { n: 14, color: T, capEnd: true, jitter: (l, i) => 1 + Math.sin(i * 1.3 + l * .7) * .035 });
    kit.lathe([[.296, -.25], [.3, -.23], [.3, -.19], [.296, -.17]], { n: 14, color: C.RUNE });
    ell(kit, 0, -.52, -.06, .22, .18, .22, [TL, TL, T], 2, { seed: 3, amount: .04 });
    kit.lathe([[.27, -.88], [.26, -.78], [.24, -.68], [.21, -.56]], { n: 14, color: TD });
    kit.lathe([[.32, -1], [.36, -.98], [.37, -.94], [.33, -.9], [.29, -.88], [.26, -.86]], { n: 16, color: bands(C.STONE_DARK, TL, TL, T, T), capStart: true, capEnd: true, sz: 1.15 });
  });
  // Sovereign sword arm: a stone arm gripping a lofted, fullered glass-and-gold
  // blade held upright, resting back.
  creature('SovereignArm', { smooth: ORG, tint: 'F0D9A0', kind: 'limb' }, kit => {
    ell(kit, 0, .02, 0, .34, .3, .32, [TL, T, TD], 2, { seed: 11, amount: .04 });
    kit.lathe([[.2, -.6], [.23, -.45], [.24, -.3], [.21, 0]], { n: 14, color: T, capStart: true });
    kit.lathe([[.23, -.68], [.26, -.65], [.265, -.6], [.26, -.55], [.23, -.52]], { n: 14, color: bands(C.BRASS, C.GOLD, C.GOLD, C.BRASS) });
    ell(kit, 0, -.88, -.04, .22, .2, .22, [T, TD, TD], 2);
    kit.group({ pos: [0, -.9, -.12], rot: [.3, 0, 0] }, () => {
      kit.tube([[0, -.36, 0], [0, -.2, 0], [0, -.04, 0]], [.055, .06, .055], { n: 12, color: C.HORN });
      kit.lathe([[0, -.5], [.06, -.46], [.08, -.4], [.06, -.36]], { n: 12, color: C.GOLD });
      gem(kit, 0, -.42, -.07, .035, .04, C.RUNE, [PI / 2, 0, 0]);
      for (const s of [-1, 1]) blade(kit, { pos: [0, .04, 0], rot: [0, 0, s * -PI / 2], len: .4, w: .14, th: .05, tip: .3, belly: .2, cols: [C.GOLD, C.BRASS] });
      blade(kit, { pos: [0, .07, 0], len: 2.1, w: .26, th: .045, tip: .02, belly: .08, m: 12, steps: 8, cols: [C.GOLD, C.GLASS, C.GLASS, C.GLASS, C.ICE] });
      kit.tube([[0, .2, 0], [0, 1.1, 0], [0, 1.6, 0]], [.03, .025, .012], { n: 10, color: C.GLINT });
    });
  });
  // Serpent coil: barrel-shaped scaled section with a cambered glass fin.
  creature('SerpentCoil', { smooth: ORG, tint: '3FB8AF', kind: 'limb' }, kit => {
    along(kit, [0, 0, .5], [[.6, -.5], [.66, -.38], [.71, -.22], [.74, -.06], [.735, .1], [.71, .26], [.66, .4], [.6, .5]], { n: 16, sz: 1.05, color: dorsal(TD, T, TL) });
    blade(kit, { pos: [0, .7, .5], rot: [-.5, 0, 0], len: .42, w: .7, th: .03, belly: .5, sweep: .2, cols: [TL, C.GLASS] });
    for (const s of [-1, 1]) blade(kit, { pos: [s * .66, -.25, .5], rot: [0, 0, s * -2.2], len: .22, w: .2, th: .02, cols: [TL] });
  });
  // Serpent tail: tapering last coils and a broad cambered fluke.
  creature('SerpentTail', { smooth: ORG, tint: '3FB8AF', kind: 'limb' }, kit => {
    along(kit, [0, 0, 0], [[0, -1.5], [.06, -1.46], [.14, -1.36], [.22, -1.2], [.3, -.98], [.38, -.7], [.45, -.38], [.5, 0]], { n: 16, color: dorsal(TD, T, TL) }, 0, PI);
    for (const s of [-1, 1]) blade(kit, { pos: [0, 0, 1.42], rot: [s > 0 ? -1.0 : -(PI - 1.0), 0, 0], len: .62, w: .4, th: .035, sweep: .15, cols: [T, TL] });
    blade(kit, { pos: [0, .38, .55], rot: [-.6, 0, 0], len: .34, w: .55, th: .025, sweep: .2, cols: [C.GLASS] });
  });
  // Crab claw: armoured arm, swollen palm, toothed upper and lower jaws.
  creature('CrabClaw', { smooth: ORG, tint: 'D9774B', kind: 'limb' }, kit => {
    kit.tube([[0, 0, 0], [.13, 0, -.05], [.26, 0, -.13], [.37, 0, -.24], [.45, 0, -.34]], [.135, .13, .125, .118, .11], { n: 12, color: bands(T, TD, T, T) });
    kit.group({ pos: [.26, 0, -.13], rot: [0, -.7, PI / 2] }, () => kit.lathe([[.135, -.03], [.145, -.01], [.145, .01], [.135, .03]], { n: 12, color: TL }));
    ell(kit, .5, 0, -.52, .26, .2, .3, [TD, T, TL], 2);
    for (const s of [-1, 1]) {
      kit.tube([[.52, s * .07, -.76], [.54, s * .1, -.88], [.55, s * .1, -1.0], [.53, s * .07, -1.1], [.5, s * .03, -1.17]], [.11, .095, .075, .05, .025], { n: 12, color: s > 0 ? TD : T });
      for (const t of [.85, .97, 1.07]) horn(kit, [[.54, s * .05, -t], [.54, s * .0, -t - .01], [.54, -s * .03, -t - .02]], .025, C.BONE);
    }
    for (const [y, z] of [[.17, -.42], [.15, -.6]]) gem(kit, .5, y, z, .05, .04, TL);
  });
  // Tier overlays -------------------------------------------------------------
  // Boss crown: a moulded brass circlet with lofted spikes and gem sockets.
  creature('OverlayCrown', { smooth: HARD, tint: 'FF3B3B', kind: 'overlay' }, kit => {
    kit.lathe([[.5, 0], [.535, .02], [.545, .06], [.545, .15], [.535, .2], [.5, .22]], { n: 24, color: bands(C.BRASS, C.GOLD, C.BRASS, C.GOLD, C.BRASS) });
    kit.lathe([[.45, .22], [.48, .17], [.48, .05], [.45, 0]], { n: 24, color: C.IRON });
    for (let i = 0; i < 8; i++) {
      const a = i * PI / 4, big = i % 2 === 0, r = .52;
      blade(kit, { pos: [Math.cos(a) * r, .18, Math.sin(a) * r], rot: [0, PI / 2 - a, 0], len: big ? .48 : .28, w: .2, th: .05, tip: .05, belly: .25, cols: [C.GOLD, C.GOLD, C.BRASS] });
      if (big) gem(kit, Math.cos(a) * (r + .03), .32, Math.sin(a) * (r + .03), .055, .07, T, [0, PI / 2 - a, PI / 2]);
    }
  });
  // World boss crown: a tall double crown of lofted spikes under a floating halo torus (n = 48).
  creature('OverlayWorldCrown', { smooth: HARD, tint: 'FFD166', kind: 'overlay' }, kit => {
    kit.lathe([[.5, 0], [.55, .03], [.565, .1], [.565, .22], [.55, .28], [.52, .3]], { n: 28, color: bands(C.BRASS, C.GOLD, C.BRASS, C.GOLD, C.BRASS) });
    kit.lathe([[.44, .3], [.5, .22], [.5, .06], [.44, 0]], { n: 28, color: C.INK });
    for (let i = 0; i < 12; i++) {
      const a = i * PI / 6, h = [.85, .5, .62][i % 3];
      blade(kit, { pos: [Math.cos(a) * .53, .26, Math.sin(a) * .53], rot: [0, PI / 2 - a, 0], len: h, w: .17, th: .045, steps: 4, tip: .05, belly: .25, cols: [C.GOLD, C.GOLD, C.BRASS] });
      if (h > .8) gem(kit, Math.cos(a) * .56, .55, Math.sin(a) * .56, .055, .09, T, [0, PI / 2 - a, PI / 2]);
    }
    torus(kit, { pos: [0, 1.15, 0], R: .66, r: .045, n: 40, color: C.GOLD });
    for (let i = 0; i < 6; i++) { const a = i * PI / 3 + PI / 6; gem(kit, Math.cos(a) * .66, 1.15, Math.sin(a) * .66, .055, .1, T) }
  });
  // Armour pauldron (brute and up): three layered domed plates with rolled rims, a horn spike, domed rivets.
  creature('OverlayPauldron', { smooth: HARD, tint: 'B0B8C4', kind: 'overlay' }, kit => {
    for (let k = 0; k < 3; k++) {
      kit.group({ pos: [k * .08, -k * .12, 0], rot: [0, 0, -.35 - k * .15] }, () =>
        kit.lathe([[.43 - k * .06, -.06], [.45 - k * .06, -.03], [.44 - k * .06, .01], [.4 - k * .06, .08], [.33 - k * .06, .15], [.22 - k * .04, .21], [.1, .245], [0, .25]], {
          n: 18, sz: .9, color: bands(C.BRASS, C.BRASS, k === 0 ? T : TD, k === 0 ? T : TD, k === 0 ? TL : T, k === 0 ? TL : T, TL), capStart: true }));
    }
    horn(kit, [[.05, .2, 0], [.09, .33, .0], [.13, .46, .01], [.16, .6, .03]], .07, C.BONE, 12);
    for (let i = 0; i < 5; i++) { const a = i * .55 - 1.1; rivet(kit, Math.sin(a) * .42, -.02, Math.cos(a) * .42 * .9, .03, C.BRASS, a + PI, 0) }
  });
  // Elite horns: a swept pair (n = 12) joined by a lofted bone brow plate.
  creature('OverlayHorns', { smooth: ORG, tint: 'EDE2C4', kind: 'overlay' }, kit => {
    for (const s of [-1, 1]) horn(kit, [[s * .16, 0, 0], [s * .3, .06, .03], [s * .42, .16, .08], [s * .5, .3, .14], [s * .54, .46, .24], [s * .52, .62, .36], [s * .45, .75, .47]], .13, C.BONE, 12);
    roundBox(kit, { pos: [0, -.01, 0], len: .16, w: .7, h: .1, steps: 3, m: 16, shape: t => [1, .8 + .2 * Math.sin(t * PI), 0], cols: [C.HORN] });
  });
  // Rune ring: the ground circle under a boss (stance-tinted): two flattened tori and twelve rune gems.
  creature('OverlayRuneRing', { smooth: 62, tint: 'FF3B3B', kind: 'overlay' }, kit => {
    torus(kit, { pos: [0, .02, 0], R: 1, r: .045, n: 40, flat: .5, color: T });
    torus(kit, { pos: [0, .02, 0], R: .83, r: .025, flat: .5, color: TD });
    for (let i = 0; i < 12; i++) { const a = i * PI / 6; gem(kit, Math.cos(a) * .915, .02, Math.sin(a) * .915, i % 2 ? .035 : .06, .02, TL) }
  });

  // Brambleback Boar (hip 1.9): a barrel-bodied boar with a bramble mane.
  creature('CreatureBoar', { smooth: ORG, tint: 'A0683D', kind: 'creature', boss: true }, kit => {
    along(kit, [0, .1, 0], [[0, -2.55], [.32, -2.5], [.62, -2.35], [.9, -2.1], [1.12, -1.75], [1.26, -1.3], [1.33, -.8], [1.35, -.3], [1.34, .2], [1.3, .6], [1.22, 1.0], [1.1, 1.35], [.95, 1.62], [.85, 1.78]],
      { n: 20, sx: .92, sz: 1.02, color: dorsal(TD, T, TL), jitter: (l, i) => l > 2 && l < 12 ? 1 + Math.sin(i * 1.7 + l * 2.1) * .025 : 1 });
    along(kit, [0, .3, -1.75], [[.75, 0], [.86, .2], [.9, .42], [.86, .65], [.76, .88], [.62, 1.1], [.52, 1.32], [.46, 1.52], [.43, 1.7], [.43, 1.75]], { n: 16, sx: .95, color: dorsal(TD, T, TL) }, .1);
    along(kit, [0, -.08, -3.4], [[.43, 0], [.43, .06], [.42, .12], [.37, .17], [.25, .2]], { n: 16, capEnd: true, capColor: TL, color: TL }, .05);
    for (const s of [-1, 1]) {
      horn(kit, [[s * .32, -.25, -3.2], [s * .48, -.24, -3.33], [s * .58, -.12, -3.4], [s * .62, .05, -3.42], [s * .58, .22, -3.36], [s * .52, .33, -3.28]], .095, C.BONE, 12);
      kit.group({ pos: [s * .62, 1.15, -2.2], rot: [-.2, 0, s * .55] }, () => kit.lathe([[.11, 0], [.14, .1], [.13, .25], [.08, .4], [0, .48]], { n: 12, sz: .45, color: bands(TD, TD, T, TL), capStart: true }));
    }
    eyes(kit, .55, .62, -2.9, .15, C.AMBER);
    // Bramble mane: cambered leaf blades with bone thorns along the spine.
    for (let i = 0; i < 7; i++) {
      const z = -1.95 + i * .6, y = 1.3 - Math.abs(z + .2) * .1;
      blade(kit, { pos: [0, y, z], rot: [-.5, (i - 4) * .06, 0], len: .62 - Math.abs(i - 3) * .05, w: .4, th: .07, belly: .35, camber: .05, m: 8, steps: 3, cols: [C.LEAF_DARK, C.MOSS, C.LEAF] });
      if (i % 3 === 1) for (const s of [-1, 1]) horn(kit, [[s * .22, y - .05, z], [s * .4, y + .08, z + .05], [s * .52, y + .24, z + .1]], .05, C.BONE);
    }
    kit.tube([[0, .55, 2.35], [.04, .74, 2.58], [.06, .9, 2.56], [0, .98, 2.42]], [.09, .075, .05, .03], { n: 10, color: TD });
  });
  rig('boar', { hip: 1.9, hitbox: [3, 3.4, 6.4], gait: 'quad', core: 'CreatureBoar', stride: 2.2, breath: .06,
    segs: [
      { shape: 'HoofLeg', at: [-.78, -.5, -1.3], role: 'legA', k: 1.42 }, { shape: 'HoofLeg', at: [.78, -.5, -1.3], role: 'legB', k: 1.42 },
      { shape: 'HoofLeg', at: [-.78, -.5, 1.3], role: 'legB', k: 1.42 }, { shape: 'HoofLeg', at: [.78, -.5, 1.3], role: 'legA', k: 1.42 }],
    glow: glowEyes(.55, .62, -2.9, .15, 'FFE680'), anchors: { crown: [0, 1.35, -2.15], shoulder: [1.05, .9, -1.35], chest: [0, .2, -2.3], ring: 2.4 } });

  // Thornling (hip 1.8): a walking flower bulb on roots, vine arms.
  creature('CreatureThornling', { smooth: ORG, tint: '8BC34A', kind: 'creature' }, kit => {
    kit.lathe([[.55, -.9], [.6, -.7], [.62, -.5], [.56, -.25], [.5, 0], [.52, .25], [.6, .55], [.72, .95]], { n: 16, color: bands(TD, TD, T, T, T, T, TL), jitter: (l, i) => 1 + Math.sin(i * 2.1 + l * 1.3) * .06 });
    ell(kit, 0, 1.9, 0, 1.15, 1.08, 1.12, [T, T, TL], 2, { seed: 3, amount: .02 });
    for (let i = 0; i < 6; i++) {
      const a = i * PI / 3 + PI / 6;
      blade(kit, { pos: [Math.cos(a) * .5, 2.65, Math.sin(a) * .5], rot: [-.5, PI / 2 - a + PI / 2, 0], len: 1.15, w: .78, th: .07, belly: .45, camber: -.1, m: 8, steps: 3, cols: [C.CRIMSON, C.ROSE, C.ROSE] });
    }
    ell(kit, 0, 3.05, 0, .38, .3, .38, C.AMBER, 1);
    for (let i = 0; i < 6; i++) { const a = i * PI / 3; horn(kit, [[Math.cos(a) * .25, 3.25, Math.sin(a) * .25], [Math.cos(a) * .32, 3.4, Math.sin(a) * .32], [Math.cos(a) * .34, 3.5, Math.sin(a) * .34]], .04, C.GOLD) }
    eyes(kit, .42, 2.05, -1.0, .17, C.GLINT);
    along(kit, [0, 1.55, -1.04], [[.42, -.06], [.46, -.02], [.46, .02], [.42, .06]], { n: 16, sz: .25, color: C.SOCKET, capStart: true, capEnd: true });
    for (const x of [-.25, 0, .25]) horn(kit, [[x, 1.7, -1.06], [x, 1.62, -1.08], [x, 1.55, -1.08]], .04, C.BONE);
    for (let i = 0; i < 4; i++) { const a = i * 1.7; horn(kit, [[Math.cos(a) * .55, -.4 + i * .33, Math.sin(a) * .55], [Math.cos(a) * .68, -.36 + i * .22, Math.sin(a) * .68], [Math.cos(a) * .8, -.32 + i * .22, Math.sin(a) * .8]], .06, C.BONE) }
    kit.lathe([[.85, .9], [.95, .98], [.98, 1.06], [.86, 1.14], [.7, 1.2]], { n: 16, color: C.LEAF_DARK });
  });
  rig('thornling', { hip: 1.8, hitbox: [3, 5, 3], gait: 'roots', core: 'CreatureThornling', stride: 1.6, breath: .08,
    segs: [0, 1, 2, 3].map(i => ({ shape: 'RootLeg', at: [Math.cos(i * PI / 2 + PI / 4) * .45, -.7, Math.sin(i * PI / 2 + PI / 4) * .45], rot: [0, -(i * PI / 2 + PI / 4), 0], role: i % 2 ? 'legA' : 'legB', k: [1.25, 1.15, 1.25] }))
      .concat([{ shape: 'VineArm', at: [-.72, .7, -.1], rot: [0, 0, -.5], role: 'arm', mirror: 'yaw', k: 1.6 }, { shape: 'VineArm', at: [.72, .7, -.1], rot: [0, 0, .5], role: 'arm', k: 1.6 }]),
    glow: glowEyes(.42, 2.05, -1.0, .17, 'F6FF8F').concat([{ kind: 'core', at: [0, 3.05, 0], r: .3, color: 'FFD166' }]),
    anchors: { crown: [0, 3.3, 0], shoulder: [.75, 1.1, 0], chest: [0, 1.9, -1.1], ring: 2 } });

  // Shale Crawler (hip 1.1): armoured segmented crawler with mandibles.
  creature('CreatureCrawler', { smooth: ORG, tint: '8D8A82', kind: 'creature' }, kit => {
    const segs = [[-1.7, .9, .85], [-.45, 1.05, .95], [.85, 1.0, .9], [2.0, .78, .72]];
    segs.forEach(([z, r, h], i) => {
      along(kit, [0, 0, z], [[0, -.62], [r * .55, -.58], [r * .82, -.45], [r, -.22], [r, .2], [r * .82, .43], [r * .55, .56], [0, .62]], { n: 16, sz: h / r, color: dorsal(TD, T, TL) });
      along(kit, [0, .05, z], [[r * 1.04, -.48], [r * 1.1, -.36], [r * 1.13, -.12], [r * 1.12, .12], [r * 1.08, .32], [r * 1.02, .44]], { n: 16, sz: h / r, color: (l, k, p) => p[2] > -.05 ? (l === 0 || l === 4 ? C.STONE_LIGHT : C.SLATE) : C.STONE });
      if (i < 3) spines(kit, [[h * 1.1, z + .1, .35, .5, -.6]], C.STONE_LIGHT, .07);
    });
    for (const s of [-1, 1]) horn(kit, [[s * .35, -.25, -2.3], [s * .44, -.28, -2.55], [s * .42, -.31, -2.82], [s * .25, -.32, -3.05], [s * .07, -.3, -3.15]], .12, C.BONE, 12);
    for (const s of [-1, 1]) kit.tube([[s * .3, .5, -2.3], [s * .45, .8, -2.48], [s * .65, 1.08, -2.58], [s * .9, 1.35, -2.45]], [.045, .04, .03, .015], { n: 10, color: TD });
    eyes(kit, .42, .35, -2.42, .13, C.EMBER);
  });
  rig('crawler', { hip: 1.1, hitbox: [3.4, 2.4, 6.4], gait: 'hex', core: 'CreatureCrawler', stride: 1.4, breath: .04,
    segs: [-1.4, -.2, 1.0].flatMap((z, i) => [
      { shape: 'ChitinLeg', at: [.78, -.25, z], rot: [0, .15 - i * .15, 0], role: i % 2 ? 'legB' : 'legA', k: [1.35, 1.0, 1.35] },
      { shape: 'ChitinLeg', at: [-.78, -.25, z], rot: [0, -.15 + i * .15, 0], role: i % 2 ? 'legA' : 'legB', mirror: 'yaw', k: [1.35, 1.0, 1.35] }]),
    glow: glowEyes(.42, .35, -2.42, .13, 'FF9F43'), anchors: { crown: [0, 1.0, -1.7], shoulder: [.9, .7, -.5], chest: [0, .2, -2.2], ring: 2.6 } });

  // Cinder Mite (hip 1.3): a round ember tick, glowing cracks on its abdomen.
  creature('CreatureMite', { smooth: ORG, tint: 'B5543A', kind: 'creature' }, kit => {
    ell(kit, 0, .1, .35, 1.25, 1.1, 1.3, [TD, T, TL], 2, { seed: 13, amount: .02 });
    ell(kit, 0, .35, 1.75, 1.0, .95, 1.0, [C.INK, TD, T], 2, { seed: 17, amount: .03 });
    // Inset ember cracks: thin glowing tubes hugging the abdomen.
    for (let i = 0; i < 5; i++) {
      const a = -.9 + i * .45, pts = [];
      for (let s = 0; s <= 6; s++) { const b = -.9 + s * .3; pts.push([Math.sin(a) * Math.cos(b) * 1.0, .35 + Math.cos(a) * Math.cos(b) * .96, 1.75 + Math.sin(b) * 1.0]) }
      kit.tube(pts, .045, { n: 10, color: C.FLAME });
    }
    ell(kit, 0, -.08, -1.12, .65, .6, .58, [TD, TD, T], 2);
    for (const s of [-1, 1]) horn(kit, [[s * .25, -.45, -1.5], [s * .28, -.6, -1.58], [s * .25, -.74, -1.6], [s * .15, -.82, -1.52]], .09, C.BONE);
    for (let i = 0; i < 5; i++) { const a = i * .5 - 1; horn(kit, [[Math.sin(a) * .9, 1.05, .1 + i * .2], [Math.sin(a) * .98, 1.2, .15 + i * .2], [Math.sin(a) * 1.05, 1.35, .2 + i * .2]], .08, C.HORN) }
    eyes(kit, .3, .1, -1.6, .12, C.FLAME);
  });
  rig('mite', { hip: 1.3, hitbox: [3.6, 2.6, 4.4], gait: 'hex', core: 'CreatureMite', stride: 1.3, breath: .05,
    segs: [-.6, 0, .6, 1.2].flatMap((z, i) => [
      { shape: 'ChitinLeg', at: [.95, -.35, z], rot: [0, .4 - i * .27, 0], role: i % 2 ? 'legB' : 'legA', k: 1.25 },
      { shape: 'ChitinLeg', at: [-.95, -.35, z], rot: [0, -.4 + i * .27, 0], role: i % 2 ? 'legA' : 'legB', mirror: 'yaw', k: 1.25 }]),
    glow: glowEyes(.3, .1, -1.6, .12, 'FFD23F').concat([{ kind: 'rune', at: [0, 1.32, 1.75], r: .22, color: 'FF8A3D' }]),
    anchors: { crown: [0, 1.15, .2], shoulder: [1.0, .8, .1], chest: [0, .1, -1.2], ring: 2 } });

  // Bark Stalker (hip 2.7): a lean wooden wolf-stag with branch antlers.
  creature('CreatureStalker', { smooth: ORG, tint: '6E5A3E', kind: 'creature', boss: true }, kit => {
    along(kit, [0, .35, 0], [[0, -2.3], [.3, -2.25], [.55, -2.1], [.78, -1.85], [.92, -1.5], [.98, -1.0], [1.0, -.4], [1.05, .1], [1.1, .6], [1.1, 1.0], [1.05, 1.4], [.92, 1.75], [.75, 2.0]],
      { n: 20, sx: .9, color: dorsal(TD, T, TL), jitter: (l, i) => l > 0 && l < 12 ? 1 + Math.sin(i * 2.3 + l * 1.9) * .045 : 1 });
    kit.tube([[0, .9, -1.8], [0, 1.15, -2.1], [0, 1.4, -2.45], [0, 1.6, -2.85]], [.6, .55, .5, .45], { n: 16, color: bands(T, T, TD) });
    along(kit, [0, 1.55, -2.65], [[.5, 0], [.53, .18], [.51, .38], [.44, .62], [.36, .88], [.27, 1.1], [.18, 1.3], [.08, 1.38], [0, 1.4]], { n: 16, sz: .82, color: dorsal(TD, T, TL) }, .08);
    along(kit, [0, 1.1, -2.85], [[.32, 0], [.32, .25], [.29, .5], [.22, .75], [.12, .95], [0, 1.05]], { n: 14, sz: .4, color: TD }, -.1);
    for (const x of [-.18, -.06, .06, .18]) horn(kit, [[x, 1.3, -3.55], [x, 1.22, -3.6], [x, 1.15, -3.6]], .03, C.BONE);
    eyes(kit, .32, 1.72, -3.2, .12, C.MINT);
    for (const s of [-1, 1]) {
      horn(kit, [[s * .25, 2.0, -2.5], [s * .38, 2.3, -2.42], [s * .5, 2.6, -2.3], [s * .58, 2.9, -2.15], [s * .62, 3.2, -2.0], [s * .55, 3.6, -1.7]], .1, C.BARK, 12);
      horn(kit, [[s * .5, 2.6, -2.3], [s * .7, 2.72, -2.4], [s * .9, 2.85, -2.45], [s * 1.1, 3.05, -2.4]], .055, C.BARK);
      horn(kit, [[s * .6, 3.15, -2.0], [s * .78, 3.25, -1.98], [s * .95, 3.35, -1.95]], .04, C.BARK);
      blade(kit, { pos: [s * 1.1, 3.05, -2.4], rot: [0, 0, s * -.4], len: .36, w: .22, th: .02, camber: .03, m: 8, steps: 3, cols: [C.LEAF_DARK, C.LEAF] });
    }
    for (const [y, z, h, l] of [[1.4, -1.6, .6, .7], [1.45, -.6, .55, .7], [1.42, .4, .5, .65], [1.3, 1.4, .4, .55]]) blade(kit, { pos: [0, y, z], rot: [-.45, 0, 0], len: h, w: l, th: .07, m: 8, steps: 3, cols: [C.MOSS] });
  });
  rig('stalker', { hip: 2.7, hitbox: [3, 4.6, 6.4], gait: 'quad', core: 'CreatureStalker', stride: 3.2, breath: .07,
    segs: [
      { shape: 'PawLeg', at: [-.7, -.35, -1.35], role: 'legA', k: [2.0, 2.35, 2.0] }, { shape: 'PawLeg', at: [.7, -.35, -1.35], role: 'legB', k: [2.0, 2.35, 2.0] },
      { shape: 'PawLeg', at: [-.7, -.35, 1.35], role: 'legB', k: [2.0, 2.35, 2.0] }, { shape: 'PawLeg', at: [.7, -.35, 1.35], role: 'legA', k: [2.0, 2.35, 2.0] },
      { shape: 'FurTail', at: [0, .8, 2.2], role: 'tail', k: 2.0 }],
    glow: glowEyes(.32, 1.72, -3.2, .12, 'C7FF6B'), anchors: { crown: [0, 2.05, -2.55], shoulder: [.85, 1.1, -1.3], chest: [0, .4, -2.0], ring: 2.6 } });

  // Gale Sprite (hip 4, flying): a swirling wind spirit with a gust tail.
  creature('CreatureSprite', { smooth: ORG, tint: 'A8DADC', kind: 'creature' }, kit => {
    ell(kit, 0, 0, 0, .95, 1.0, .95, [TL, T, T], 2);
    kit.group({ rot: [-PI / 2 - .4, 0, 0] }, () => kit.lathe([[.85, 0], [.75, -.3], [.62, -.6], [.5, -.9], [.4, -1.2], [.3, -1.5], [.22, -1.8], [.14, -2.05], [.08, -2.3], [0, -2.6]], {
      n: 14, color: bands(T, T, TL, T, TL, T, TL, TL, TL), wobble: (l) => [Math.sin(l * .9) * .18, 0] }));
    for (const [R, t, y] of [[1.15, .35, .1], [1.3, -.4, -.2], [1.0, .9, .4]]) torus(kit, { rot: [t, 0, 0], pos: [0, y, 0], R, r: .035, n: 28, color: TL });
    eyes(kit, .36, .2, -.82, .14, C.NAVY);
    along(kit, [0, -.2, -.92], [[.12, -.02], [.14, 0], [.12, .02]], { n: 12, sz: .3, color: C.SOCKET, capStart: true, capEnd: true });
    for (let i = 0; i < 5; i++) { const a = i * 2 * PI / 5; gem(kit, Math.cos(a) * .55, .95, Math.sin(a) * .55, .07, .26, C.ICE) }
  });
  rig('sprite', { hip: 4, hitbox: [3.2, 3.2, 3.2], gait: 'fly', core: 'CreatureSprite', flap: 9, breath: .1,
    segs: [{ shape: 'GlassWing', at: [.7, .4, .25], rot: [0, -.35, .35], role: 'wing', k: 1.6 }, { shape: 'GlassWing', at: [-.7, .4, .25], rot: [0, .35, -.35], role: 'wing', mirror: 'roll', k: 1.6 }],
    glow: glowEyes(.36, .2, -.82, .14, 'E9F5FF').concat([{ kind: 'core', at: [0, 0, 0], r: .5, color: 'F1FAEE', orbit: 0 },
      { kind: 'mote', at: [1.8, .3, 0], r: .18, color: 'F1FAEE', orbit: 1.6 }, { kind: 'mote', at: [-1.8, -.2, 0], r: .18, color: 'F1FAEE', orbit: 1.6 }]),
    anchors: { crown: [0, 1.0, 0], chest: [0, -.1, -.9], ring: 1.8 } });

  // Brass Golem (hip 3.4): lofted boiler torso (n = 28) with raised trim bands
  // and inset panel seams, domed rivets, a helm with brow, visor slot and jaw
  // guard, chest furnace socket and n = 12 flue pistons.
  creature('CreatureGolem', { smooth: HARD, tint: 'D4A84B', kind: 'creature', boss: true }, kit => {
    kit.lathe([[1.0, -.75], [1.2, -.68], [1.35, -.55], [1.5, -.25], [1.6, .2], [1.62, .3], [1.62, .36], [1.68, .9], [1.7, 1.3], [1.62, 1.62], [1.6, 1.7], [1.55, 1.8], [1.35, 2.0], [1.05, 2.15]],
      { n: 24, sz: .75, color: bands(TD, TD, T, T, T, C.BRASS, T, T, T, C.BRASS, TL, TL, T) });
    for (const y of [.55, 1.45]) kit.lathe([[1.665 - (y - .9) * (y - .9) * .1, y - .02], [1.64 - (y - .9) * (y - .9) * .1, y], [1.665 - (y - .9) * (y - .9) * .1, y + .02]], { n: 24, sz: .75, color: C.IRON });
    for (let l = 0; l < 2; l++) for (let i = 0; i < 5; i++) { const a = PI + .6 + i * (PI - 1.2) / 4, y = .33 + l * 1.33, r = l ? 1.61 : 1.62; rivet(kit, Math.cos(a) * r, y, Math.sin(a) * r * .75, .05, C.BRASS, PI / 2 - a + PI, 0) }
    kit.group({ pos: [0, .9, -1.18], rot: [-PI / 2, 0, 0] }, () => kit.lathe([[.62, 0], [.67, .04], [.68, .09], [.62, .14], [.52, .18], [.42, .2]], { n: 20, color: bands(C.IRON, C.BRASS, C.BRASS, C.IRON, C.IRON), capEnd: true, capColor: C.SOCKET }));
    kit.lathe([[1.0, -1.35], [1.08, -1.28], [1.1, -1.1], [1.06, -.9], [1.0, -.75]], { n: 20, sz: .75, color: C.IRON, capStart: true });
    // Helm: a lofted dome with a brow ridge, a dark visor slot and a jaw guard.
    kit.group({ pos: [0, 2.35, -.1] }, () => {
      kit.lathe([[.62, 0], [.7, .12], [.76, .3], [.78, .45], [.79, .55], [.77, .62], [.72, .75], [.62, .92], [.44, 1.06], [.22, 1.14], [0, 1.17]], { n: 16, sz: .9, color: bands(TD, TD, T, C.SOCKET, C.SOCKET, T, T, TL, TL, TL), capStart: true });
      roundBox(kit, { pos: [0, .7, -.62], len: .2, w: 1.4, h: .14, steps: 2, m: 16, cols: [C.BRASS] });
      roundBox(kit, { pos: [0, .2, -.6], len: .25, w: 1.0, h: .32, steps: 2, m: 16, shape: t => [1 - t * .1, 1, 0], cols: [TD] });
      kit.lathe([[.15, 1.12], [.17, 1.22], [.1, 1.36], [0, 1.42]], { n: 12, color: C.BRASS });
    });
    for (const s of [-1, 1]) kit.group({ pos: [s * .8, 0, 1.05] }, () => {
      kit.lathe([[.24, 1.8], [.26, 2.65], [.33, 2.85], [.3, 3.05]], { n: 12, color: bands(TD, C.IRON, C.IRON), capStart: true });
    });
  });
  rig('golem', { hip: 3.4, hitbox: [5.2, 7, 3], gait: 'biped', core: 'CreatureGolem', stride: 2.6, breath: .05,
    segs: [
      { shape: 'GolemLeg', at: [-.75, -1.25, 0], role: 'legA', k: [1.7, 2.15, 1.7] }, { shape: 'GolemLeg', at: [.75, -1.25, 0], role: 'legB', k: [1.7, 2.15, 1.7] },
      { shape: 'GolemArm', at: [-2.05, 1.85, 0], role: 'armB', mirror: 'yaw', k: 2.3 }, { shape: 'GolemArm', at: [2.05, 1.85, 0], role: 'armA', k: 2.3 }],
    glow: [{ kind: 'eye', at: [0, 2.9, -.98], r: .2, color: '5CE1E6', bar: [1.0, .14] }, { kind: 'core', at: [0, .9, -1.32], r: .38, color: '5CE1E6' }],
    anchors: { crown: [0, 3.95, -.1], shoulder: [2.05, 2.25, 0], chest: [0, .9, -1.4], ring: 3.2 } });

  // Storm Harrier (hip 5, flying): sleek raptor, hooked gold beak, layered crest and tail fan.
  creature('CreatureHarrier', { smooth: ORG, tint: '7B8CDE', kind: 'creature', boss: true }, kit => {
    along(kit, [0, 0, 0], [[0, -1.6], [.2, -1.56], [.38, -1.42], [.55, -1.2], [.7, -.9], [.76, -.5], [.78, -.1], [.74, .3], [.68, .6], [.6, .85], [.5, 1.1], [.46, 1.3], [.45, 1.4]], { n: 18, sz: .95, color: dorsal(TD, T, TL) });
    ell(kit, 0, .38, -1.65, .55, .52, .6, [TD, T, TL], 2);
    kit.group({ pos: [0, .22, -2.15], rot: [-PI / 2 + .55, 0, 0] }, () => kit.lathe([[.2, 0], [.19, .1], [.16, .22], [.12, .34], [.07, .46], [0, .55]], { n: 14, sx: .8, color: C.GOLD, capStart: true }));
    horn(kit, [[0, .12, -2.42], [0, .06, -2.5], [0, -.04, -2.53], [0, -.14, -2.48], [0, -.2, -2.42]], .07, C.GOLD, 12);
    eyes(kit, .35, .55, -1.95, .11, C.GLINT);
    for (let i = 0; i < 3; i++) blade(kit, { pos: [0, .78 - i * .05, -1.55 + i * .32], rot: [-1.0 - i * .15, 0, 0], len: .7 - i * .15, w: .22, th: .03, tip: .08, belly: .3, m: 8, steps: 3, cols: [T, C.ICE] });
    for (let i = -2; i <= 2; i++) blade(kit, { pos: [i * .15, .05, 1.35], rot: [PI / 2 - .1, i * .26, 0], len: 1.1 - Math.abs(i) * .12, w: .24, th: .025, tip: .3, belly: .2, m: 8, steps: 3, cols: [TD, T, TL] });
    for (const s of [-1, 1]) {
      kit.tube([[s * .3, -.55, .2], [s * .31, -.72, .24], [s * .32, -.88, .22], [s * .3, -1.05, .1]], [.1, .09, .075, .06], { n: 12, color: C.GOLD });
      for (const a of [-.35, .35]) kit.group({ pos: [s * .3, -1.05, .05], rot: [-1.0, a, 0] }, () => horn(kit, [[0, 0, 0], [0, .08, 0], [0, .15, .05]], .035, C.CLAW));
    }
    for (let i = 0; i < 4; i++) blade(kit, { pos: [0, .55 - i * .04, -.9 + i * .55], rot: [-1.35, 0, 0], len: .35, w: .5 - i * .04, th: .02, tip: .3, m: 8, steps: 3, cols: [TD] });
  });
  rig('harrier', { hip: 5, hitbox: [6, 2.4, 4.4], gait: 'fly', core: 'CreatureHarrier', flap: 5, breath: .06,
    segs: [{ shape: 'FeatherWing', at: [.6, .25, -.2], role: 'wing', k: [3.6, 2.2, 2.8] }, { shape: 'FeatherWing', at: [-.6, .25, -.2], role: 'wing', mirror: 'roll', k: [3.6, 2.2, 2.8] }],
    glow: glowEyes(.35, .55, -1.95, .11, 'E9F5FF').concat([{ kind: 'rune', at: [0, .95, -1.35], r: .16, color: 'CFE8FF' }]),
    anchors: { crown: [0, .9, -1.6], shoulder: [.6, .5, -.3], chest: [0, -.2, -1.3], ring: 3 } });

  // Gloomfang Spider (hip 1.6): a banded abdomen with a sigil, thorax, eye
  // cluster, chelicerae and fangs.
  creature('CreatureSpider', { smooth: ORG, tint: '4B3F72', kind: 'creature', boss: true }, kit => {
    kit.group({ pos: [0, .5, 1.35], rot: [-PI / 2 - .2, 0, 0] }, () => kit.lathe([[0, -1.55], [.5, -1.45], [.88, -1.2], [1.15, -.85], [1.3, -.45], [1.38, 0], [1.36, .4], [1.24, .8], [1.0, 1.15], [.66, 1.4], [.3, 1.53], [0, 1.56]],
      { n: 22, sx: 1.0, sz: .92, color: bands(TL, TD, T, TD, T, TD, T, TD, T, TL, TL) }));
    ell(kit, 0, .05, -.55, .9, .7, .95, [TD, TD, T], 2);
    ell(kit, 0, .05, -1.35, .55, .5, .5, [TD, TD, T], 2);
    const eyePts = [[-.3, .35, -1.72, .11], [.3, .35, -1.72, .11], [-.52, .18, -1.58, .08], [.52, .18, -1.58, .08], [-.15, .52, -1.65, .07], [.15, .52, -1.65, .07]];
    for (const [x, y, z, r] of eyePts) eye(kit, x, y, z, r, C.ROSE);
    for (const s of [-1, 1]) {
      kit.tube([[s * .22, -.2, -1.6], [s * .25, -.35, -1.7], [s * .26, -.5, -1.74]], [.15, .13, .11], { n: 12, color: T });
      horn(kit, [[s * .26, -.5, -1.74], [s * .24, -.66, -1.72], [s * .17, -.8, -1.62], [s * .1, -.86, -1.52]], .1, C.BONE, 12);
    }
    for (let i = 1; i < 5; i++) horn(kit, [[(i - 2.5) * .35, 1.62, .9 + (i % 2) * .5], [(i - 2.5) * .37, 1.75, .95 + (i % 2) * .5], [(i - 2.5) * .4, 1.88, 1.0 + (i % 2) * .5]], .06, C.HORN);
  });
  rig('spider', { hip: 1.6, hitbox: [6, 3, 5.6], gait: 'octo', core: 'CreatureSpider', stride: 1.6, breath: .04,
    segs: [-1.0, -.6, -.2, .2].flatMap((z, i) => [
      { shape: 'SpiderLeg', at: [.62, .05, z], rot: [0, .55 - i * .37, 0], role: i % 2 ? 'legB' : 'legA', k: [2.4, 1.95, 2.4] },
      { shape: 'SpiderLeg', at: [-.62, .05, z], rot: [0, -.55 + i * .37, 0], role: i % 2 ? 'legA' : 'legB', mirror: 'yaw', k: [2.4, 1.95, 2.4] }]),
    glow: [[-.3, .35, -1.72, .11], [.3, .35, -1.72, .11], [-.52, .18, -1.58, .08], [.52, .18, -1.58, .08]].map(([x, y, z, r]) => ({ kind: 'eye', at: [x, y, z - r * .55], r: r * .62, color: 'D65DB1' }))
      .concat([{ kind: 'rune', at: [0, 1.78, 1.25], r: .24, color: 'B388EB' }]),
    anchors: { crown: [0, .75, -.6], shoulder: [.9, .55, -.5], chest: [0, 0, -1.4], ring: 3.2 } });

  // Void Wisp (hip 4, floating): a flame-crowned orb in a torus cage.
  creature('CreatureWisp', { smooth: ORG, tint: '6A4C93', kind: 'creature' }, kit => {
    kit.lathe([[0, -.95], [.35, -.88], [.62, -.7], [.82, -.4], [.9, -.05], [.86, .25], [.7, .55], [.5, .85], [.36, 1.15], [.25, 1.45], [.15, 1.68], [0, 1.9]],
      { n: 18, color: bands(TD, TD, T, T, T, T, TL, TL, TL, TL, TL), wobble: (l) => [0, l >= 7 ? (l - 6) * .08 : 0] });
    for (const [t, y] of [[.45, 0], [-.45, .1]]) torus(kit, { pos: [0, y, 0], rot: [t, 0, 0], R: 1.25, r: .045, n: 32, color: C.INK });
    for (let i = 0; i < 3; i++) ell(kit, 0, -.9 - i * .5, .35 + i * .45, .35 - i * .08, .35 - i * .08, .35 - i * .08, T, 1);
    eyes(kit, .28, .15, -.78, .12, C.GLINT);
  });
  rig('wisp', { hip: 4, hitbox: [3.4, 3.4, 3.4], gait: 'float', core: 'CreatureWisp', breath: .12,
    segs: [0, 1, 2, 3].map(i => ({ shape: 'WispShard', at: [Math.cos(i * PI / 2) * 1.9, (i % 2 ? .3 : -.2), Math.sin(i * PI / 2) * 1.9], role: 'orbit', k: 1.3, phase: i * PI / 2 })),
    glow: glowEyes(.28, .15, -.78, .12, 'FFFFFF').concat([{ kind: 'core', at: [0, 0, 0], r: .55, color: 'C9B6FF' }]),
    anchors: { crown: [0, 1.95, 0], chest: [0, 0, -.9], ring: 2 } });

  // Reef Lurker (hip 1.6): a toothy angler-lizard with a glowing lure and fins.
  creature('CreatureLurker', { smooth: ORG, tint: '4F8FBF', kind: 'creature', boss: true }, kit => {
    along(kit, [0, 0, .3], [[.45, -2.5], [.68, -2.4], [.88, -2.2], [1.02, -1.85], [1.1, -1.4], [1.14, -.9], [1.15, -.4], [1.16, .1], [1.15, .5], [1.11, .95], [1.05, 1.4], [.98, 1.75], [.95, 1.9]], { n: 22, sz: 1.05, color: dorsal(TD, T, TL) });
    along(kit, [0, .15, -1.7], [[1.0, 0], [1.1, .2], [1.15, .42], [1.13, .66], [1.06, .92], [.92, 1.18], [.72, 1.4], [.45, 1.56], [.2, 1.65], [0, 1.68]], { n: 20, sz: .85, color: dorsal(TD, T, TL) }, .05);
    along(kit, [0, -.45, -1.6], [[.9, 0], [.95, .3], [.92, .6], [.78, .95], [.55, 1.3], [.28, 1.55], [0, 1.65]], { n: 18, sz: .35, color: TD }, -.12);
    for (let i = 0; i < 8; i++) { const a = -1.2 + i * .34; horn(kit, [[Math.sin(a) * .82, -.2, -2.55 - Math.cos(a) * .55], [Math.sin(a) * .82, -.32, -2.57 - Math.cos(a) * .55], [Math.sin(a) * .8, -.46 - (i % 3) * .04, -2.58 - Math.cos(a) * .55]], .055, C.BONE) }
    eyes(kit, .62, .65, -2.85, .16, C.AMBER);
    kit.tube([[0, 1.2, -1.9], [0, 1.55, -1.98], [0, 1.85, -2.25], [0, 1.98, -2.6], [0, 1.95, -2.85]], [.08, .072, .062, .052, .045], { n: 12, color: TD });
    for (const [y, z, h, l] of [[1.08, -1.4, .7, .9], [1.15, -.4, .8, 1.0], [1.15, .6, .7, .9], [1.05, 1.5, .55, .7]]) blade(kit, { pos: [0, y, z], rot: [-.45, 0, 0], len: h, w: l, th: .05, m: 8, steps: 3, cols: [TL] });
    for (const s of [-1, 1]) blade(kit, { pos: [s * 1.0, -.6, -.5], rot: [PI / 2, 0, s * -1.1], len: .9, w: .6, th: .035, belly: .4, sweep: .25, cols: [T, TL] });
  });
  rig('lurker', { hip: 1.6, hitbox: [3, 3.6, 7.6], gait: 'slither', core: 'CreatureLurker', stride: 2.4, breath: .06,
    segs: [{ shape: 'FishTail', at: [0, .05, 2.2], role: 'tail', k: [2.6, 2.6, 2.6] }],
    glow: glowEyes(.62, .65, -2.85, .16, 'FFE66D').concat([{ kind: 'core', at: [0, 2.05, -2.95], r: .26, color: 'B8FFF4' }]),
    anchors: { crown: [0, 1.25, -1.6], shoulder: [.95, .6, -1.0], chest: [0, -.2, -2.4], ring: 3.4 } });

  // Tempest Wraith (hip 3.6, floating): hooded storm-cloak with folds, torn
  // cloth strips and a void face.
  creature('CreatureWraith', { smooth: ORG, tint: '4A5A7A', kind: 'creature', boss: true }, kit => {
    kit.lathe([[1.55, -2.85], [1.42, -2.5], [1.3, -2.15], [1.18, -1.7], [1.06, -1.2], [.98, -.7], [.95, -.2], [1.02, .25], [1.1, .6], [1.02, .9], [.9, 1.12], [.6, 1.4]], {
      n: 28, sz: .78, color: bands(TL, TL, T, T, T, T, TD, TD, TD, TD, TD),
      jitter: (l, i) => 1 + Math.sin(i * PI * 6 / 28) * .07 * (l < 7 ? 1 : .3) + (l === 0 ? (hash(l, i, 61) - .5) * .4 : 0), lift: (l, i) => l === 0 ? (hash(l, i, 62) - .2) * .8 : 0 });
    for (let i = 0; i < 6; i++) { const a = PI * .15 + i * PI * .34; blade(kit, { pos: [Math.cos(a) * 1.25, -2.6, Math.sin(a) * .95], rot: [PI, PI / 2 - a, 0], len: .5 + (i % 3) * .18, w: .32, th: .015, tip: .2, belly: .15, m: 8, steps: 3, cols: [TL] }) }
    // Hood with a folded rim, the void face and a brass clasp.
    kit.lathe([[.62, 1.2], [.85, 1.35], [.97, 1.6], [1.0, 1.85], [.95, 2.1], [.8, 2.4], [.55, 2.62], [.25, 2.75], [0, 2.78]], { n: 22, color: bands(TD, T, T, T, T, TD, TD, TD), jitter: (l, i) => 1 + Math.sin(i * PI * 4 / 22) * .035 });
    ell(kit, 0, 1.6, -.48, .66, .72, .5, C.VOID, 2);
    torus(kit, { pos: [0, 1.25, -.02], R: .66, r: .05, n: 24, color: C.BRASS });
    for (let i = 0; i < 5; i++) { const a = i * .5 - 1; gem(kit, Math.sin(a) * .98, .5 + Math.abs(a) * .2, -Math.cos(a) * .76, .06, .14, C.ICE, [PI / 2, a, 0]) }
    eye(kit, -.27, 1.7, -.86, .1, C.ICE); eye(kit, .27, 1.7, -.86, .1, C.ICE);
  });
  rig('wraith', { hip: 3.6, hitbox: [4, 5.6, 3], gait: 'float', core: 'CreatureWraith', breath: .12,
    segs: [{ shape: 'WraithArm', at: [1.0, .9, -.3], rot: [-.3, 0, .35], role: 'armA', k: 2.4 }, { shape: 'WraithArm', at: [-1.0, .9, -.3], rot: [-.3, 0, -.35], role: 'armB', mirror: 'yaw', k: 2.4 }],
    glow: glowEyes(.27, 1.7, -.86, .1, '7FDBFF').concat([0, 1, 2].map(i => ({ kind: 'mote', at: [Math.cos(i * 2.1) * 1.7, 2.6, Math.sin(i * 2.1) * 1.7], r: .14, color: 'CFE8FF', orbit: 1.4 }))),
    anchors: { crown: [0, 2.7, .05], shoulder: [1.0, 1.1, 0], chest: [0, .6, -.9], ring: 2.4 } });

  // Starborn Sentinel (hip 4.2): marble titan, carved pectorals, a filigree
  // gold girdle, inset rune grooves, a star core, a crystal head and a halo.
  creature('CreatureSentinel', { smooth: ORG, tint: '5FA8D3', kind: 'creature', boss: true }, kit => {
    kit.lathe([[.95, -1.25], [1.12, -.9], [1.32, -.4], [1.5, .2], [1.62, .8], [1.6, 1.3], [1.48, 1.85], [1.15, 2.28], [.75, 2.48], [.5, 2.55]],
      { n: 24, sz: .7, color: bands(C.GOLD, TL, T, T, TL, TL, T, TD, TD) });
    for (const s of [-1, 1]) ell(kit, s * .62, 1.55, -.95, .6, .45, .3, [TL, TL, T], 2, { seed: 5, amount: .02 });
    for (const s of [-1, 1]) ell(kit, s * .3, .45, -1.0, .27, .26, .18, [TL, T, T], 1);
    for (let i = 0; i < 4; i++) { const a = PI + .7 + i * (PI - 1.4) / 3; kit.group({ pos: [Math.cos(a) * 1.5, 1.0, Math.sin(a) * 1.05], rot: [0, PI / 2 - a, 0] }, () => kit.tube([[0, -.35, 0], [0, 0, 0], [0, .35, 0]], .025, { n: 10, color: C.RUNE })) }
    kit.lathe([[1.0, -1.25], [1.2, -1.36], [1.24, -1.52], [1.1, -1.7], [.85, -1.85]], { n: 20, sz: .7, color: bands(C.BRASS, C.GOLD, C.BRASS, C.IRON), capEnd: true });
    kit.group({ pos: [0, 1.0, -1.08], rot: [-PI / 2, 0, 0] }, () => kit.lathe([[.6, 0], [.68, .06], [.6, .11], [.5, .13]], { n: 16, color: C.GOLD, capEnd: true, capColor: C.SOCKET }));
    kit.group({ pos: [0, 3.15, 0] }, () => kit.lathe([[0, -.75], [.28, -.5], [.48, -.2], [.55, .05], [.48, .3], [.3, .62], [0, .95]], { n: 12, color: bands(TD, TL, C.ICE, C.ICE, C.ICE, C.GLINT) }));
    torus(kit, { pos: [0, 3.3, .1], rot: [PI / 2, 0, 0], R: 1.45, r: .07, n: 28, color: C.GOLD });
    for (let i = 0; i < 4; i++) { const a = i * PI / 2 + PI / 4; gem(kit, Math.cos(a) * 1.45, 3.3 + Math.sin(a) * 1.45, .1, .1, .16, C.GOLD, [PI / 2, 0, a]) }
  });
  rig('sentinel', { hip: 4.2, hitbox: [5.4, 8.4, 3], gait: 'biped', core: 'CreatureSentinel', stride: 2.4, breath: .05,
    segs: [
      { shape: 'StoneLeg', at: [-.8, -1.5, 0], role: 'legA', k: [1.8, 2.75, 1.8] }, { shape: 'StoneLeg', at: [.8, -1.5, 0], role: 'legB', k: [1.8, 2.75, 1.8] },
      { shape: 'StoneArm', at: [-2.05, 1.8, 0], role: 'armB', mirror: 'yaw', k: [2.2, 3.0, 2.2] }, { shape: 'StoneArm', at: [2.05, 1.8, 0], role: 'armA', k: [2.2, 3.0, 2.2] },
      ...[0, 1, 2, 3].map(i => ({ shape: 'CrystalShard', at: [Math.cos(i * PI / 2 + PI / 4) * 3.0, 1.2, Math.sin(i * PI / 2 + PI / 4) * 3.0], role: 'orbit', k: 1.6, phase: i * PI / 2 }))],
    glow: [{ kind: 'core', at: [0, 1.0, -1.2], r: .45, color: 'FFD166' }, { kind: 'eye', at: [0, 3.2, -.55], r: .18, color: 'FFF4C2' }],
    anchors: { crown: [0, 4.15, 0], shoulder: [2.05, 2.25, 0], chest: [0, 1.0, -1.25], ring: 3.4 } });

  // Serpent (hip 2.2): horned sea-serpent head and neck (coils follow).
  creature('CreatureSerpent', { smooth: ORG, tint: '3FB8AF', kind: 'creature', boss: true }, kit => {
    kit.tube([[0, -.9, -.2], [0, -.5, -.75], [0, -.1, -1.3], [0, .25, -1.85], [0, .6, -2.4], [0, .8, -2.8], [0, .95, -3.15]], [.85, .82, .78, .74, .7, .66, .62], { n: 20, color: (i, k, p) => p[1] > -.2 + i * .2 + .4 ? TD : T });
    for (let i = 0; i < 4; i++) along(kit, [0, -.85 + i * .45, -.25 - i * .75], [[.62, -.12], [.66, 0], [.62, .12]], { n: 16, sx: .8, sz: .55, color: TL }, -.6);
    along(kit, [0, 1.15, -3.2], [[.75, 0], [.83, .2], [.86, .42], [.8, .7], [.68, .98], [.5, 1.25], [.3, 1.5], [.12, 1.6], [0, 1.62]], { n: 20, sz: .85, color: dorsal(TD, T, TL) }, .05);
    along(kit, [0, .62, -3.3], [[.6, 0], [.62, .3], [.56, .6], [.42, .9], [.22, 1.15], [0, 1.25]], { n: 16, sz: .35, color: TD }, -.15);
    for (let i = 0; i < 6; i++) { const a = -1.1 + i * .44; horn(kit, [[Math.sin(a) * .45, .72, -4.1 - Math.cos(a) * .3], [Math.sin(a) * .45, .62, -4.12 - Math.cos(a) * .3], [Math.sin(a) * .43, .52, -4.12 - Math.cos(a) * .3]], .04, C.BONE) }
    eyes(kit, .55, 1.45, -4.1, .15, C.GOLD);
    for (const s of [-1, 1]) {
      horn(kit, [[s * .45, 1.75, -3.4], [s * .56, 2.0, -3.22], [s * .65, 2.25, -3.0], [s * .7, 2.45, -2.75], [s * .7, 2.6, -2.45], [s * .6, 2.75, -2.0]], .14, C.BONE, 12);
      kit.tube([[s * .62, .95, -4.3], [s * .82, .86, -4.38], [s * 1.0, .75, -4.4], [s * 1.2, .62, -4.32], [s * 1.38, .45, -4.15], [s * 1.55, .2, -3.9]], [.05, .045, .04, .033, .027, .02], { n: 10, color: TL });
    }
    for (let i = 0; i < 4; i++) blade(kit, { pos: [0, .55 + i * .32, -.6 - i * .8], rot: [-.55, 0, 0], len: .6, w: .7, th: .03, belly: .45, sweep: .2, m: 8, steps: 3, cols: [TL, C.GLASS] });
  });
  rig('serpent', { hip: 2.2, hitbox: [3, 4.4, 9.4], gait: 'slither', core: 'CreatureSerpent', stride: 3, breath: .05,
    segs: [
      { shape: 'SerpentCoil', at: [0, -.85, -.2], role: 'coil', k: 1.05, phase: 0 }, { shape: 'SerpentCoil', at: [0, -1.15, .9], role: 'coil', k: .95, phase: 1 },
      { shape: 'SerpentCoil', at: [0, -1.35, 1.9], role: 'coil', k: .82, phase: 2 }, { shape: 'SerpentTail', at: [0, -1.5, 2.8], role: 'coil', k: 1.2, phase: 3 }],
    glow: glowEyes(.55, 1.45, -4.1, .15, 'F6FF8F'), anchors: { crown: [0, 2.0, -3.4], shoulder: [.75, .9, -1.4], chest: [0, .2, -2.6], ring: 3.6 } });

  // Crab (hip 1.4): ridged, spiked shell with coral growths and stalked eyes.
  creature('CreatureCrab', { smooth: ORG, tint: 'D9774B', kind: 'creature', boss: true }, kit => {
    kit.lathe([[1.75, -.45], [1.92, -.32], [2.02, -.15], [2.05, .1], [1.98, .28], [1.8, .48], [1.48, .66], [1.1, .82], [.7, .92], [.32, .97], [0, .98]],
      { n: 28, sz: .78, color: bands(TL, TD, T, T, TD, T, T, T, TL, TL), jitter: (l, i) => l === 3 ? 1 + Math.sin(i * PI * 7 / 28) * .035 : 1 });
    kit.lathe([[1.7, -.7], [1.73, -.6], [1.75, -.45]], { n: 28, sz: .78, color: TL, capStart: true, capColor: TL });
    for (let i = 0; i < 9; i++) { const a = PI + .3 + i * (PI - .6) / 8; horn(kit, [[Math.cos(a) * 1.95, .05, Math.sin(a) * 1.5], [Math.cos(a) * 2.08, .08, Math.sin(a) * 1.6], [Math.cos(a) * 2.25, .12, Math.sin(a) * 1.72]], .1, C.BONE) }
    for (let i = 0; i < 6; i++) { const a = i * 1.05 + .3; ell(kit, Math.cos(a) * .85, .84, Math.sin(a) * .62, .22, .12, .2, C.CORAL, 1, { seed: 20 + i, amount: .08 }) }
    for (const s of [-1, 1]) {
      kit.tube([[s * .42, .55, -1.3], [s * .44, .85, -1.38], [s * .45, 1.15, -1.46], [s * .45, 1.35, -1.5]], [.1, .09, .08, .07], { n: 12, color: TD });
      ell(kit, s * .45, 1.5, -1.52, .2, .2, .2, C.SOCKET, 1);
      along(kit, [s * .45, 1.5, -1.66], [[.11, 0], [.1, .04], [.06, .08], [0, .09]], { n: 12, color: C.AMBER, capStart: true });
    }
    for (const x of [-.25, 0, .25]) horn(kit, [[x, -.05, -1.56], [x, -.15, -1.6], [x, -.27, -1.58]], .06, C.BONE);
  });
  rig('crab', { hip: 1.4, hitbox: [6.2, 2.8, 4.4], gait: 'hex', core: 'CreatureCrab', stride: 1.4, breath: .04,
    segs: [-.5, .4, 1.3].flatMap((z, i) => [
      { shape: 'ChitinLeg', at: [1.5, -.35, z], rot: [0, .2 - i * .25, 0], role: i % 2 ? 'legB' : 'legA', k: [1.6, 1.2, 1.6] },
      { shape: 'ChitinLeg', at: [-1.5, -.35, z], rot: [0, -.2 + i * .25, 0], role: i % 2 ? 'legA' : 'legB', mirror: 'yaw', k: [1.6, 1.2, 1.6] }])
      .concat([{ shape: 'CrabClaw', at: [1.45, -.05, -1.2], rot: [0, -.25, 0], role: 'claw', k: 1.6 }, { shape: 'CrabClaw', at: [-1.45, -.05, -1.2], rot: [0, .25, 0], role: 'claw', mirror: 'roll', k: 1.6 }]),
    glow: [{ kind: 'eye', at: [-.45, 1.5, -1.75], r: .1, color: 'FFE680' }, { kind: 'eye', at: [.45, 1.5, -1.75], r: .1, color: 'FFE680' }],
    anchors: { crown: [0, .95, 0], shoulder: [1.4, .5, -.6], chest: [0, .2, -1.5], ring: 3.2 } });

  // Ray (hip 2.8, flying): a manta disc with cephalic horns and a whip tail.
  creature('CreatureRay', { smooth: ORG, tint: '8FB8D6', kind: 'creature' }, kit => {
    along(kit, [0, 0, .2], [[0, -2.0], [.3, -1.95], [.6, -1.75], [.9, -1.4], [1.1, -.9], [1.2, -.3], [1.18, .2], [1.1, .65], [.92, 1.1], [.7, 1.45], [.45, 1.75], [.2, 1.88], [0, 1.9]], { n: 20, sz: .42, color: dorsal(TD, T, C.FUR) });
    kit.tube([[0, 0, 1.9], [0, .02, 2.35], [0, .05, 2.8], [0, .08, 3.25], [0, .12, 3.7], [0, .17, 4.15], [0, .2, 4.6]], [.16, .13, .1, .075, .055, .035, .02], { n: 10, color: TD });
    blade(kit, { pos: [0, .2, 4.45], rot: [-PI / 2 + .3, 0, 0], len: .4, w: .2, th: .02, cols: [TL] });
    for (const s of [-1, 1]) kit.tube([[s * .55, 0, -1.6], [s * .65, -.02, -1.85], [s * .7, -.08, -2.1], [s * .68, -.2, -2.3], [s * .62, -.3, -2.45]], [.16, .14, .11, .08, .05], { n: 12, color: TD });
    eyes(kit, .82, .25, -1.45, .12, C.ICE);
    for (const [x, z] of [[-.45, .3], [.45, .55], [0, .95], [-.3, 1.3], [.3, -.3]]) along(kit, [x, .33, z], [[.1, 0], [.08, .015], [0, .025]], { n: 12, color: C.ICE, capStart: true }, -PI / 2);
  });
  rig('ray', { hip: 2.8, hitbox: [7.4, 1.8, 5.4], gait: 'glide', core: 'CreatureRay', flap: 2.2, breath: .08,
    segs: [{ shape: 'RayFin', at: [.95, 0, .2], role: 'wing', k: [2.6, 1.0, 2.9] }, { shape: 'RayFin', at: [-.95, 0, .2], role: 'wing', mirror: 'roll', k: [2.6, 1.0, 2.9] }],
    glow: glowEyes(.82, .25, -1.45, .12, 'BFF7E6').concat([{ kind: 'rune', at: [0, .4, .5], r: .2, color: 'BFF7E6' }]),
    anchors: { crown: [0, .45, -.8], chest: [0, -.3, -1.2], ring: 3.4 } });

  // Driftbell Jelly (hip 3.4, floating): a bell (n = 28) with frill lobes, an
  // inner glow chamber and four oral arms.
  creature('CreatureJelly', { smooth: ORG, tint: 'B39DDB', kind: 'creature' }, kit => {
    kit.lathe([[1.7, -.05], [1.7, .15], [1.66, .45], [1.58, .8], [1.45, 1.15], [1.28, 1.5], [1.05, 1.85], [.78, 2.15], [.5, 2.4], [.25, 2.56], [0, 2.62]], { n: 28, color: bands(TD, T, T, T, TL, T, T, TL, TL, TL) });
    kit.lathe([[1.68, -.35], [1.8, -.25], [1.82, -.12], [1.72, -.04]], { n: 28, color: TL, jitter: (l, i) => 1 + Math.sin(i * PI * 8 / 28) * .06, lift: (l, i) => l === 0 ? Math.sin(i * PI * 8 / 28) * .1 : 0 });
    kit.lathe([[1.2, .1], [1.05, .2], [.8, .3], [.4, .36], [0, .38]], { n: 24, color: C.VOID });
    for (let i = 0; i < 4; i++) { const a = i * PI / 2 + PI / 4; kit.tube([[Math.cos(a) * .35, -.1, Math.sin(a) * .35], [Math.cos(a) * .48, -.5, Math.sin(a) * .48], [Math.cos(a) * .4, -.95, Math.sin(a) * .4], [Math.cos(a) * .25, -1.4, Math.sin(a) * .25]], [.16, .12, .08, .03], { n: 12, color: bands(TL, T, TL), jitter: (j, k) => 1 + Math.sin(k * PI * 4 / 12 + j) * .15 }) }
    for (let i = 0; i < 10; i++) { const a = i * PI / 5; gem(kit, Math.cos(a) * 1.42, 1.2, Math.sin(a) * 1.42, .07, .28, C.GLINT) }
    eyes(kit, .45, 1.35, -1.38, .13, C.GLINT);
  });
  rig('jelly', { hip: 3.4, hitbox: [3.8, 5.6, 3.8], gait: 'float', core: 'CreatureJelly', breath: .18, pulse: true,
    segs: [0, 1, 2, 3, 4, 5].map(i => ({ shape: 'JellyTendril', at: [Math.cos(i * PI / 3) * 1.25, -.15, Math.sin(i * PI / 3) * 1.25], role: 'tendril', k: [1.6, 2.6 + (i % 2) * .6, 1.6], phase: i })),
    glow: glowEyes(.45, 1.35, -1.38, .13, 'FFFFFF').concat([{ kind: 'core', at: [0, 1.1, 0], r: .6, color: 'E8DBFF' }]),
    anchors: { crown: [0, 2.6, 0], chest: [0, 1.0, -1.5], ring: 2.2 } });

  // Riftmaw Stalker (hip 2.2): a hulking rift hound with crystal spines.
  creature('CreatureRiftmaw', { smooth: ORG, tint: '5B3F8C', kind: 'creature' }, kit => {
    along(kit, [0, .25, .3], [[.4, -2.3], [.7, -2.2], [.95, -2.0], [1.12, -1.6], [1.2, -1.2], [1.3, -.7], [1.35, -.2], [1.45, .3], [1.5, .8], [1.45, 1.2], [1.4, 1.6], [1.25, 1.9], [1.1, 2.15]], { n: 20, sx: .9, color: dorsal(TD, T, TL) });
    along(kit, [0, .95, -2.6], [[.75, 0], [.82, .2], [.85, .4], [.8, .62], [.72, .85], [.6, 1.05], [.48, 1.25], [.3, 1.4]], { n: 18, sz: .85, color: dorsal(TD, T, TL) }, .12);
    along(kit, [0, .35, -2.7], [[.65, 0], [.66, .25], [.62, .5], [.5, .78], [.3, 1.0], [0, 1.15]], { n: 16, sz: .4, color: TD }, -.25);
    for (let i = 0; i < 7; i++) { const a = -1.1 + i * .366; horn(kit, [[Math.sin(a) * .55, .6, -3.55 - Math.cos(a) * .2], [Math.sin(a) * .55, .5, -3.56 - Math.cos(a) * .2], [Math.sin(a) * .53, .38 - (i % 2) * .08, -3.56 - Math.cos(a) * .2]], .05, C.BONE) }
    eyes(kit, .45, 1.25, -3.6, .13, C.LAVENDER);
    for (let i = 0; i < 5; i++) {
      const z = -1.8 + i * .85, h = 1.3 - i * .15;
      kit.group({ pos: [0, 1.35 - i * .05, z], rot: [-.35, 0, 0] }, () => kit.lathe([[0, -.1], [.14, .05], [.2, .25], [.2, h * .45], [.13, h * .75], [0, h]], { n: 10, color: bands(TL, TL, C.GLASS, C.GLASS, C.ICE) }));
      for (const s of [-1, 1]) kit.group({ pos: [s * .55, 1.1 - i * .05, z + .3], rot: [-.4, 0, s * .6] }, () => kit.lathe([[0, -.05], [.08, .05], [.1, .2], [0, h * .5]], { n: 10, color: C.GLASS }));
    }
  });
  rig('riftmaw', { hip: 2.2, hitbox: [3.6, 4.2, 7.2], gait: 'quad', core: 'CreatureRiftmaw', stride: 2.6, breath: .07,
    segs: [
      { shape: 'ClawLeg', at: [-.95, -.4, -1.6], role: 'legA', k: [1.7, 1.85, 1.7] }, { shape: 'ClawLeg', at: [.95, -.4, -1.6], role: 'legB', k: [1.7, 1.85, 1.7] },
      { shape: 'ClawLeg', at: [-.9, -.4, 1.6], role: 'legB', k: [1.6, 1.85, 1.6] }, { shape: 'ClawLeg', at: [.9, -.4, 1.6], role: 'legA', k: [1.6, 1.85, 1.6] },
      { shape: 'ScaleTail', at: [0, .6, 2.35], rot: [-.3, 0, 0], role: 'tail', k: 2.4 }],
    glow: glowEyes(.45, 1.25, -3.6, .13, 'C77DFF').concat([{ kind: 'rune', at: [0, 1.55, .1], r: .16, color: 'C77DFF', bar: [.18, 3.2] }]),
    anchors: { crown: [0, 1.75, -2.4], shoulder: [1.1, 1.1, -1.5], chest: [0, .3, -2.4], ring: 3.4 } });

  // Shardglass Seer (hip 3.2, floating): crystal-faced oracle in a folded robe
  // with a gold hem, hood folds, sleeves of torn strips, a halo torus.
  creature('CreatureSeer', { smooth: ORG, tint: '7A5BC4', kind: 'creature', boss: true }, kit => {
    kit.lathe([[1.35, -2.9], [1.3, -2.7], [1.22, -2.3], [1.12, -1.8], [1.02, -1.2], [.92, -.6], [.86, -.1], [.92, .4], [.95, .7], [.82, 1.0], [.6, 1.15], [.4, 1.2]], {
      n: 32, sz: .85, color: bands(C.GOLD, TL, TL, T, T, T, T, TD, TD, TD, TD), jitter: (l, i) => 1 + Math.sin(i * PI * 8 / 32) * .06 * (l < 7 ? 1 : .2), lift: (l, i) => l === 0 ? Math.sin(i * PI * 8 / 32) * .12 : 0 });
    for (let i = 0; i < 5; i++) { const a = PI * .1 + i * PI * .42; blade(kit, { pos: [Math.cos(a) * 1.3, -2.7, Math.sin(a) * 1.1], rot: [PI, PI / 2 - a, 0], len: .25 + (i % 2) * .12, w: .3, th: .014, tip: .2, belly: .15, m: 8, steps: 3, cols: [TL] }) }
    kit.group({ pos: [0, 1.65, 0] }, () => kit.lathe([[0, -.6], [.22, -.42], [.38, -.2], [.46, .05], [.4, .3], [.25, .55], [0, .8]], { n: 12, color: bands(C.ICE, C.ICE, C.ICE, C.GLINT, C.ICE, C.ICE) }));
    kit.lathe([[.85, 1.25], [.88, 1.5], [.84, 1.8], [.74, 2.1], [.58, 2.35], [.38, 2.55], [.18, 2.7], [0, 2.75]], { n: 22, sz: .95, color: bands(C.GOLD, TD, TD, TD, TD, TD, TD), jitter: (l, i) => 1 + Math.sin(i * PI * 4 / 22) * .04 });
    ell(kit, 0, 1.75, -.5, .55, .62, .3, C.VOID, 1);
    torus(kit, { pos: [0, 3.05, 0], rot: [-.25, 0, 0], R: 1.15, r: .06, n: 40, color: C.GOLD });
    for (let i = 0; i < 6; i++) { const a = i * PI / 3; gem(kit, Math.cos(a) * 1.15, 3.05 + Math.sin(a) * .28, Math.sin(a) * 1.12, .08, .16, C.ICE) }
    for (let i = 0; i < 5; i++) gem(kit, 0, .4 - i * .5, -.93 - i * .05, .1, .1, C.GOLD, [PI / 2, 0, 0]);
  });
  rig('seer', { hip: 3.2, hitbox: [3.4, 6.2, 3.4], gait: 'float', core: 'CreatureSeer', breath: .1,
    segs: [{ shape: 'WraithArm', at: [.95, .75, -.2], rot: [-.25, 0, .3], role: 'armA', k: 2.1 }, { shape: 'WraithArm', at: [-.95, .75, -.2], rot: [-.25, 0, -.3], role: 'armB', mirror: 'yaw', k: 2.1 },
      ...[0, 1, 2, 3, 4].map(i => ({ shape: 'CrystalShard', at: [Math.cos(i * 2 * PI / 5) * 2.3, .7 + (i % 2) * .5, Math.sin(i * 2 * PI / 5) * 2.3], role: 'orbit', k: 1.25, phase: i * 2 * PI / 5 }))],
    glow: [{ kind: 'eye', at: [-.2, 1.7, -.42], r: .1, color: 'FFFFFF' }, { kind: 'eye', at: [.2, 1.7, -.42], r: .1, color: 'FFFFFF' }, { kind: 'core', at: [0, 1.65, 0], r: .3, color: 'BFF4FF' }],
    anchors: { crown: [0, 2.8, 0], shoulder: [.95, 1.0, 0], chest: [0, .5, -.95], ring: 2 } });

  // Crownforged Colossus (hip 4.6): a lofted forge-construct torso (n = 28)
  // with trim bands, panel seams and rivets, a furnace core, a sculpted helm
  // with brow, visor and jaw, and a lofted crystal crest.
  creature('CreatureColossus', { smooth: HARD, tint: '8A6E9E', kind: 'creature', boss: true }, kit => {
    kit.lathe([[1.1, -1.2], [1.3, -1.08], [1.5, -.85], [1.7, -.4], [1.85, .1], [1.95, .6], [2.03, 1.0], [2.05, 1.08], [2.05, 1.16], [2.0, 1.6], [1.85, 2.2], [1.4, 2.7], [.7, 2.9]],
      { n: 24, sz: .7, color: bands(TD, TD, T, T, T, T, C.BRASS, C.GOLD, T, T, TL, T) });
    for (const y of [.4, 1.75]) kit.lathe([[1.92 - Math.abs(y - 1.1) * .1, y - .02], [1.89 - Math.abs(y - 1.1) * .1, y], [1.92 - Math.abs(y - 1.1) * .1, y + .02]], { n: 24, sz: .7, color: C.IRON });
    kit.lathe([[1.2, -1.75], [1.3, -1.62], [1.35, -1.45], [1.25, -1.28], [1.15, -1.2]], { n: 18, sz: .72, color: C.IRON, capStart: true });
    for (let l = 0; l < 2; l++) for (let i = 0; i < 5; i++) { const a = PI + .6 + i * (PI - 1.2) / 4; rivet(kit, Math.cos(a) * 1.93, .45 + l * 1.3, Math.sin(a) * 1.93 * .7, .06, C.BRASS, PI / 2 - a + PI, 0) }
    kit.group({ pos: [0, 1.2, -1.42], rot: [-PI / 2, 0, 0] }, () => kit.lathe([[.75, 0], [.8, .05], [.82, .1], [.72, .17], [.6, .22], [.5, .24]], { n: 18, color: bands(C.IRON, C.GOLD, C.GOLD, C.IRON, C.IRON), capEnd: true, capColor: C.SOCKET }));
    kit.group({ pos: [0, 2.9, -.2] }, () => {
      kit.lathe([[.75, 0], [.85, .15], [.92, .38], [.94, .52], [.94, .64], [.9, .78], [.8, .98], [.64, 1.14], [.42, 1.25], [.2, 1.3], [0, 1.32]], { n: 18, sz: .9, color: bands(TD, TD, T, C.SOCKET, C.SOCKET, T, TL, TL, TL, TL), capStart: true });
      roundBox(kit, { pos: [0, .82, -.75], len: .22, w: 1.6, h: .15, steps: 2, m: 16, cols: [C.BRASS] });
      roundBox(kit, { pos: [0, .22, -.74], len: .28, w: 1.15, h: .36, steps: 2, m: 16, shape: t => [1 - t * .1, 1, 0], cols: [TD] });
      for (let i = 0; i < 5; i++) kit.group({ pos: [(i - 2) * .36, 1.2, 0], rot: [0, 0, (i - 2) * -.18] }, () =>
        kit.lathe([[0, -.1], [.16, .15], [.17, .4], [.12, .8 - Math.abs(i - 2) * .15], [0, 1.25 - Math.abs(i - 2) * .3]], { n: 10, color: bands(TL, C.GLASS, C.GLASS, C.ICE) }));
    });
  });
  rig('colossus', { hip: 4.6, hitbox: [6.2, 9.2, 4], gait: 'biped', core: 'CreatureColossus', stride: 3, breath: .05,
    segs: [
      { shape: 'GolemLeg', at: [-.95, -1.6, 0], role: 'legA', k: [2.2, 3.0, 2.2] }, { shape: 'GolemLeg', at: [.95, -1.6, 0], role: 'legB', k: [2.2, 3.0, 2.2] },
      { shape: 'GolemArm', at: [-2.5, 2.35, 0], role: 'armB', mirror: 'yaw', k: [2.8, 3.1, 2.8] }, { shape: 'GolemArm', at: [2.5, 2.35, 0], role: 'armA', k: [2.8, 3.1, 2.8] }],
    glow: [{ kind: 'eye', at: [0, 3.65, -1.08], r: .22, color: 'FFB347', bar: [1.2, .16] }, { kind: 'core', at: [0, 1.2, -1.6], r: .48, color: 'FFB347' }],
    anchors: { crown: [0, 4.85, -.2], shoulder: [2.5, 2.85, 0], chest: [0, 1.2, -1.7], ring: 3.8 } });

  // Voidcrown Drake (hip 3.6, flying) and the Wyrm world boss.
  const drakeBody = (kit, wyrm) => {
    along(kit, [0, 0, .5], [[.3, -2.2], [.6, -2.1], [.85, -1.9], [1.02, -1.55], [1.1, -1.1], [1.14, -.6], [1.15, -.1], [1.12, .4], [1.05, .9], [.9, 1.3], [.7, 1.7], [.55, 1.88], [.45, 2.0]], { n: wyrm ? 16 : 20, sx: .95, color: dorsal(TD, T, TL) });
    kit.tube([[0, .4, -1.35], [0, .7, -1.68], [0, 1.0, -2.0], [0, 1.25, -2.35], [0, 1.45, -2.65], [0, 1.55, -2.9], [0, 1.6, -3.1]], [.62, .57, .52, .48, .44, .41, .4], { n: 14, color: (i, k, p) => p[1] > 0 ? TD : TL });
    along(kit, [0, 1.6, -3.05], [[.48, 0], [.53, .18], [.55, .38], [.5, .62], [.42, .85], [.3, 1.08], [.18, 1.28], [.08, 1.4], [0, 1.45]], { n: 16, sz: .8, color: dorsal(TD, T, TL) }, .06);
    along(kit, [0, 1.25, -3.2], [[.4, 0], [.4, .3], [.35, .6], [.25, .85], [.12, 1.05], [0, 1.15]], { n: 14, sz: .35, color: TD }, -.18);
    for (let i = 0; i < 4; i++) { const a = -.9 + i * .6; horn(kit, [[Math.sin(a) * .3, 1.4, -4.1 - Math.cos(a) * .12], [Math.sin(a) * .3, 1.33, -4.11 - Math.cos(a) * .12], [Math.sin(a) * .29, 1.25, -4.11 - Math.cos(a) * .12]], .035, C.BONE) }
    eyes(kit, .36, 1.85, -3.75, .11, C.LAVENDER);
    for (const s of [-1, 1]) {
      horn(kit, [[s * .3, 2.0, -3.2], [s * .45, 2.28, -2.9], [s * .58, 2.5, -2.55], [s * .62, 2.62, -2.25], [s * .58, 2.75, -1.8]], .14, C.HORN, wyrm ? 10 : 12);
      if (wyrm) horn(kit, [[s * .45, 1.7, -3.0], [s * .8, 1.84, -2.8], [s * 1.1, 1.86, -2.5], [s * 1.25, 1.85, -2.25]], .09, C.HORN);
    }
    for (const [y, z, h, l] of (wyrm ? [[1.2, -.6, .6, .6], [1.15, .4, .55, .6], [1.0, 1.4, .45, .55]] : [[1.75, -1.6, .55, .5], [1.2, -.6, .6, .6], [1.15, .4, .55, .6], [1.0, 1.4, .45, .55]]))
      blade(kit, { pos: [0, y, z], rot: [-.5, 0, 0], len: h, w: l, th: .06, m: 8, steps: 3, cols: [wyrm ? C.GLASS : TL] });
    kit.group({ pos: [0, -.78, .4] }, () => along(kit, [0, 0, 0], [[.5, -1.6], [.62, -1.3], [.7, -1.0], [.72, -.5], [.72, 0], [.68, .5], [.6, 1.0], [.45, 1.35], [.3, 1.6]], { n: 14, sz: .4, color: bands(TL, C.GOLD, TL, C.GOLD, TL, C.GOLD, TL, C.GOLD) }));
    if (wyrm) {
      for (let i = 0; i < 3; i++) { const a = i * .9 - .9; blade(kit, { pos: [Math.sin(a) * .5, 1.55 + Math.cos(a) * .3, -2.45], rot: [.6, a, 0], len: .62 - Math.abs(a) * .15, w: .2, th: .035, tip: .05, m: 8, steps: 3, cols: [TL, C.GLASS] }) }
    }
  };
  creature('CreatureDrake', { smooth: ORG, tint: '4B3F72', kind: 'creature' }, kit => drakeBody(kit, false));
  creature('CreatureWyrm', { smooth: ORG, tint: '2E2448', kind: 'creature', boss: true }, kit => drakeBody(kit, true));
  const drakeSegs = wyrm => [
    { shape: 'DrakeWing', at: [.75, .75, -.3], rot: [0, -.1, .15], role: 'wing', k: [wyrm ? 4.6 : 4.0, 2.5, wyrm ? 3.4 : 3.0] },
    { shape: 'DrakeWing', at: [-.75, .75, -.3], rot: [0, .1, -.15], role: 'wing', mirror: 'roll', k: [wyrm ? 4.6 : 4.0, 2.5, wyrm ? 3.4 : 3.0] },
    { shape: 'ClawLeg', at: [-.75, -.55, 1.2], rot: [.5, 0, 0], role: 'tuck', k: 1.5 }, { shape: 'ClawLeg', at: [.75, -.55, 1.2], rot: [.5, 0, 0], role: 'tuck', k: 1.5 },
    { shape: 'ScaleTail', at: [0, .1, 2.35], rot: [-.1, 0, 0], role: 'tail', k: wyrm ? 3.6 : 3.1 }]
    .concat(wyrm ? [{ shape: 'DrakeWing', at: [.6, .55, 1.0], rot: [0, -.35, .1], role: 'wing', k: [3.0, 2.0, 2.2], phase: .6 },
      { shape: 'DrakeWing', at: [-.6, .55, 1.0], rot: [0, .35, -.1], role: 'wing', mirror: 'roll', k: [3.0, 2.0, 2.2], phase: .6 }] : []);
  rig('drake', { hip: 3.6, hitbox: [5, 4, 9], gait: 'fly', core: 'CreatureDrake', flap: 3.2, breath: .06, segs: drakeSegs(false),
    glow: glowEyes(.36, 1.85, -3.75, .11, '8E7CF0').concat([{ kind: 'rune', at: [0, -1.05, .4], r: .2, color: '8E7CF0', bar: [.5, 2.6] }]),
    anchors: { crown: [0, 2.2, -3.0], shoulder: [.85, 1.0, -.9], chest: [0, .2, -1.6], ring: 4 } });
  rig('wyrm', { hip: 3.6, hitbox: [5.4, 4.4, 10], gait: 'fly', core: 'CreatureWyrm', flap: 2.8, breath: .06, segs: drakeSegs(true),
    glow: glowEyes(.36, 1.85, -3.75, .11, 'B48CFF').concat([{ kind: 'rune', at: [0, -1.05, .4], r: .22, color: 'B48CFF', bar: [.5, 2.6] }]),
    anchors: { crown: [0, 2.2, -3.0], shoulder: [.85, 1.0, -.9], chest: [0, .2, -1.6], ring: 4.4 } });

  // Sovereign (hip 4.4): the crowned marble king. Robe (n = 32) with
  // sinusoidal folds and a gold hem, a rolled fur mantle, a sculpted gold mask
  // under a glass helm, a heart gem, domed rivets on the breastplate.
  creature('CreatureSovereign', { smooth: ORG, tint: 'D9CBA3', kind: 'creature', boss: true }, kit => {
    kit.lathe([[1.0, -1.2], [1.18, -.8], [1.42, -.1], [1.58, .7], [1.6, 1.4], [1.5, 1.95], [1.2, 2.45], [.9, 2.75]], { n: 24, sz: .7, color: bands(T, C.GOLD, T, TL, TL, T, T) });
    kit.lathe([[2.0, -4.35], [2.02, -4.22], [1.95, -4.0], [1.8, -3.3], [1.6, -2.55], [1.38, -1.8], [1.18, -1.3], [1.05, -1.0]], { n: 32, sz: .8,
      color: bands(C.GOLD, C.GOLD, C.CRIMSON, C.CRIMSON, C.CRIMSON, C.CRIMSON, C.CRIMSON), jitter: (l, i) => 1 + Math.sin(i * PI * 10 / 32) * .055 * Math.min(1, (7 - l) / 4) });
    // Mantle: crimson cape over the shoulders with a rolled, tufted fur collar.
    kit.lathe([[2.22, 2.2], [2.3, 2.35], [2.3, 2.5], [2.2, 2.68], [2.0, 2.85], [1.62, 3.02], [1.2, 3.12], [.7, 3.2]], { n: 24, sz: .72,
      color: bands(C.CRIMSON, C.FUR, C.FUR, C.FUR, C.FUR, TD, TD), jitter: (l, i) => l >= 1 && l <= 4 ? 1 + Math.sin(i * PI * 12 / 24) * .045 : 1 });
    kit.group({ pos: [0, 1.4, -1.12], rot: [-PI / 2, 0, 0] }, () => kit.lathe([[.62, 0], [.7, .07], [.62, .13], [.55, .16]], { n: 16, color: C.GOLD, capEnd: true, capColor: C.SOCKET }));
    for (let i = 0; i < 6; i++) { const a = PI + .7 + i * (PI - 1.4) / 5; rivet(kit, Math.cos(a) * 1.58, 1.95, Math.sin(a) * 1.58 * .7, .06, C.GOLD, PI / 2 - a + PI, 0) }
    // Helm: a glass dome over a sculpted gold mask with brow and cheek guards.
    ell(kit, 0, 4.1, -.1, .85, .9, .85, C.GLASS, 2);
    kit.group({ pos: [0, 4.0, -.55] }, () => kit.lathe([[0, -.55], [.32, -.5], [.52, -.32], [.6, -.08], [.61, .1], [.58, .25], [.5, .4], [.3, .52], [0, .55]],
      { n: 18, sz: .45, color: bands(C.GOLD, C.GOLD, C.BRASS, C.SOCKET, C.GOLD, C.BRASS, C.GOLD, C.GOLD) }));
    for (let i = 0; i < 3; i++) gem(kit, 0, -1.8 - i * .8, -1.18 - i * .2, .13, .13, C.GOLD, [PI / 2, 0, 0]);
  });
  rig('sovereign', { hip: 4.4, hitbox: [6, 9.4, 4], gait: 'biped', core: 'CreatureSovereign', stride: 2.2, breath: .05,
    segs: [
      { shape: 'StoneLeg', at: [-.8, -2.05, 0], role: 'legA', k: [1.6, 2.35, 1.6] }, { shape: 'StoneLeg', at: [.8, -2.05, 0], role: 'legB', k: [1.6, 2.35, 1.6] },
      { shape: 'StoneArm', at: [-2.4, 2.15, 0], role: 'armB', mirror: 'yaw', k: [2.0, 3.0, 2.0] }, { shape: 'SovereignArm', at: [2.4, 2.15, 0], role: 'armA', k: [2.0, 3.0, 2.0] },
      ...[0, 1, 2, 3].map(i => ({ shape: 'CrystalShard', at: [Math.cos(i * PI / 2 + PI / 4) * 3.6, 2.2, Math.sin(i * PI / 2 + PI / 4) * 3.6], role: 'orbit', k: 1.9, phase: i * PI / 2 }))],
    glow: [{ kind: 'eye', at: [-.3, 4.15, -.85], r: .14, color: 'FFE08A' }, { kind: 'eye', at: [.3, 4.15, -.85], r: .14, color: 'FFE08A' }, { kind: 'core', at: [0, 1.4, -1.25], r: .45, color: 'FFE08A' }],
    anchors: { crown: [0, 4.55, -.1], shoulder: [2.4, 2.55, 0], chest: [0, 1.4, -1.3], ring: 4 } });

  // Hollowcap Shrieker (hip 2.2): a towering mushroom (cap n = 32) with gill
  // fins, raised spots and a gaping mouth.
  creature('CreatureShrieker', { smooth: ORG, tint: 'C88B5A', kind: 'creature' }, kit => {
    kit.lathe([[.85, -1.9], [.8, -1.6], [.75, -1.2], [.68, -.7], [.65, -.2], [.66, .3], [.72, .7], [.8, 1.1]], { n: 14, color: bands(C.CLOTH, C.CLOTH, C.FUR, C.CLOTH, C.FUR, C.CLOTH, C.FUR), jitter: (l, i) => 1 + Math.sin(i * 1.9 + l) * .04 });
    kit.lathe([[2.2, .95], [2.32, 1.08], [2.35, 1.25], [2.28, 1.48], [2.12, 1.75], [1.85, 2.08], [1.5, 2.38], [1.1, 2.62], [.62, 2.8], [.25, 2.88], [0, 2.9]], { n: 32, color: bands(TD, TD, T, T, T, T, T, TL, TL, TL) });
    kit.lathe([[.75, 1.05], [1.2, .98], [1.7, .93], [2.2, .95]], { n: 32, color: C.FUR });
    for (let i = 0; i < 8; i++) { const a = i * PI / 4 + PI / 8; blade(kit, { pos: [Math.cos(a) * .8, 1.0, Math.sin(a) * .8], rot: [PI / 2, -a + PI / 2, PI / 2], len: 1.35, w: .14, th: .02, tip: .4, belly: .1, m: 8, steps: 3, cols: [C.CLOTH] }) }
    kit.lathe([[.9, .45], [1.0, .5], [1.05, .55], [1.0, .6], [.9, .65]], { n: 14, color: C.FUR, jitter: (l, i) => l === 2 ? 1 + Math.sin(i * PI * 6 / 18) * .08 : 1 });
    for (const [a, h, r] of [[.3, 2.15, .3], [2.8, 2.0, .32], [4.0, 2.5, .22], [1.0, 2.75, .2]]) {
      const rr = h > 2.6 ? .5 : h > 2.3 ? 1.35 : 1.75;
      ell(kit, Math.cos(a) * rr, h + .05, Math.sin(a) * rr, r, .08, r, C.FUR, 1);
    }
    ell(kit, 0, -.35, -.66, .42, .3, .12, C.SOCKET, 1);
    for (const x of [-.2, .2]) horn(kit, [[x, -.12, -.72], [x, -.2, -.75], [x, -.28, -.75]], .045, C.BONE);
    eyes(kit, .32, .25, -.72, .12, C.AMBER);
  });
  rig('shrieker', { hip: 2.2, hitbox: [4.4, 5, 4.4], gait: 'roots', core: 'CreatureShrieker', stride: 1.2, breath: .09, pulse: true,
    segs: [0, 1, 2].map(i => ({ shape: 'RootLeg', at: [Math.cos(i * 2 * PI / 3 + PI / 2) * .65, -1.75, Math.sin(i * 2 * PI / 3 + PI / 2) * .65], rot: [0, -(i * 2 * PI / 3 + PI / 2), 0], role: i % 2 ? 'legA' : 'legB', k: [1.0, .5, 1.0] })),
    glow: glowEyes(.32, .25, -.72, .12, 'E9F5B0').concat([0, 1, 2, 3, 4].map(i => ({ kind: 'mote', at: [Math.cos(i * 2 * PI / 5) * 1.55, 2.2, Math.sin(i * 2 * PI / 5) * 1.55], r: .24, color: 'E9F5B0' }))),
    anchors: { crown: [0, 2.9, 0], chest: [0, 0, -.8], ring: 2.6 } });

  // Mirrorscale Basilisk (hip 1.4): a long lizard plated with mirror scales.
  creature('CreatureBasilisk', { smooth: ORG, tint: '6F8F7A', kind: 'creature' }, kit => {
    along(kit, [0, 0, .2], [[.3, -2.4], [.55, -2.3], [.75, -2.1], [.88, -1.7], [.93, -1.2], [.95, -.5], [.94, .2], [.9, .9], [.78, 1.5], [.62, 2.0], [.45, 2.3]], { n: 18, color: dorsal(TD, T, TL) });
    along(kit, [0, .3, -2.45], [[.6, 0], [.66, .2], [.68, .4], [.62, .7], [.5, .98], [.32, 1.3], [.15, 1.48], [0, 1.55]], { n: 16, sz: .78, color: dorsal(TD, T, TL) }, .05);
    eyes(kit, .42, .58, -3.55, .12, C.GOLD);
    for (let i = 0; i < 9; i++) { const z = -1.9 + i * .47; along(kit, [0, .9 - Math.abs(z) * .04, z], [[.3, -.03], [.32, 0], [.3, .03], [0, .045]], { n: 16, sz: .45, color: bands(C.GLASS, C.GLASS, C.GLINT), capStart: true }, -PI / 2 - .25) }
    for (let i = 0; i < 5; i++) blade(kit, { pos: [0, 1.0 - i * .08, -3.0 + i * .3], rot: [-.6, 0, 0], len: .5 - i * .06, w: .4, th: .03, cols: [TL, C.GLASS] });
  });
  rig('basilisk', { hip: 1.4, hitbox: [3, 2.8, 8.4], gait: 'quad', core: 'CreatureBasilisk', stride: 1.8, breath: .04, sprawl: true,
    segs: [
      { shape: 'ClawLeg', at: [-.8, -.35, -1.4], rot: [0, 0, -.35], role: 'legA', k: 1.15 }, { shape: 'ClawLeg', at: [.8, -.35, -1.4], rot: [0, 0, .35], role: 'legB', k: 1.15 },
      { shape: 'ClawLeg', at: [-.8, -.35, 1.3], rot: [0, 0, -.35], role: 'legB', k: 1.15 }, { shape: 'ClawLeg', at: [.8, -.35, 1.3], rot: [0, 0, .35], role: 'legA', k: 1.15 },
      { shape: 'ScaleTail', at: [0, .05, 2.45], role: 'tail', k: [2.0, 2.0, 1.9] }],
    glow: glowEyes(.42, .58, -3.55, .12, 'E9FBFF'), anchors: { crown: [0, .95, -2.6], shoulder: [.8, .7, -1.5], chest: [0, 0, -2.4], ring: 3.6 } });

  // Thundercrag Gargant (hip 4): a crag giant (sub-3 torso mass) with glowing
  // inset cracks under a soft thunderhead.
  creature('CreatureGargant', { smooth: ORG, tint: '6F7B8C', kind: 'creature' }, kit => {
    ell(kit, 0, 1.0, 0, 2.35, 2.05, 1.55, [TL, T, TD], 3, { seed: 51, amount: .035 });
    ell(kit, 0, -1.25, 0, 1.55, .8, 1.15, [T, TD, TD], 1, { seed: 52, amount: .05 });
    ell(kit, 0, 3.55, -.35, 1.0, .85, .95, [TL, T, TD], 2, { seed: 53, amount: .06 });
    // Glowing cracks: thin tubes pressed into the torso.
    for (const [x0, y0, x1, y1] of [[-.9, 2.0, -.3, .4], [.5, 2.3, .9, .9], [1.1, 1.6, 1.6, .9]]) {
      const pts = [];
      for (let s = 0; s <= 4; s++) { const t = s / 4, x = x0 + (x1 - x0) * t + Math.sin(t * 9) * .08, y = y0 + (y1 - y0) * t; const zz = -Math.sqrt(Math.max(.01, 1 - (x / 2.35) ** 2 - ((y - 1) / 2.05) ** 2)) * 1.55 * .985; pts.push([x, y, zz]) }
      kit.tube(pts, .05, { n: 10, color: C.RUNE });
    }
    for (let i = 0; i < 3; i++) { const a = i * 2.1 + .4; ell(kit, Math.cos(a) * .85, 5.1, Math.sin(a) * .65 + .3, .7, .5, .62, C.STONE_LIGHT, 1, { seed: 60 + i, amount: .05 }) }
    ell(kit, 0, 5.3, .3, 1.0, .65, .9, C.GLINT, 1, { seed: 70, amount: .05 });
    for (const s of [-1, 1]) horn(kit, [[s * 1.7, 2.3, .5], [s * 1.95, 2.5, .68], [s * 2.15, 2.7, .82]], .22, C.STONE_DARK);
  });
  rig('gargant', { hip: 4, hitbox: [6.4, 9, 4], gait: 'biped', core: 'CreatureGargant', stride: 2.8, breath: .06,
    segs: [
      { shape: 'StoneLeg', at: [-1.05, -1.75, 0], role: 'legA', k: [2.2, 2.3, 2.2] }, { shape: 'StoneLeg', at: [1.05, -1.75, 0], role: 'legB', k: [2.2, 2.3, 2.2] },
      { shape: 'StoneArm', at: [-2.65, 2.2, .1], role: 'armB', mirror: 'yaw', k: [2.8, 4.1, 2.8] }, { shape: 'StoneArm', at: [2.65, 2.2, .1], role: 'armA', k: [2.8, 4.1, 2.8] }],
    glow: [{ kind: 'eye', at: [0, 3.55, -1.3], r: .18, color: 'BFE4FF', bar: [1.0, .14] }, { kind: 'core', at: [0, 5.2, .3], r: .55, color: 'BFE4FF', flicker: true }],
    anchors: { crown: [0, 4.35, -.35], shoulder: [2.6, 2.7, 0], chest: [0, 1.2, -1.55], ring: 3.8 } });

  // Umbral Dreadmaw (hip 2.2): a shadow beast with tattered shade fins.
  creature('CreatureDreadmaw', { smooth: ORG, tint: '2B2238', kind: 'creature' }, kit => {
    along(kit, [0, .2, .4], [[.35, -2.4], [.65, -2.3], [.9, -2.1], [1.08, -1.75], [1.2, -1.2], [1.28, -.6], [1.3, -.1], [1.38, .4], [1.4, .9], [1.35, 1.3], [1.25, 1.75], [1.08, 2.1], [.9, 2.35]], { n: 20, sx: .88, color: dorsal(C.VOID, T, TD) });
    along(kit, [0, .95, -2.7], [[.78, 0], [.86, .2], [.88, .45], [.82, .7], [.72, .95], [.58, 1.15], [.42, 1.35], [.2, 1.45]], { n: 18, sz: .82, color: dorsal(C.VOID, T, TD) }, .1);
    along(kit, [0, .3, -2.85], [[.7, 0], [.71, .28], [.66, .55], [.52, .8], [.3, 1.02], [0, 1.15]], { n: 16, sz: .42, color: TD }, -.3);
    for (let i = 0; i < 7; i++) { const a = -1.12 + i * .373; horn(kit, [[Math.sin(a) * .6, .58, -3.7 - Math.cos(a) * .2], [Math.sin(a) * .6, .46, -3.71 - Math.cos(a) * .2], [Math.sin(a) * .58, .32 - (i % 2) * .1, -3.71 - Math.cos(a) * .2]], .05, C.BONE) }
    eyes(kit, .48, 1.3, -3.75, .13, C.LAVENDER);
    for (let i = 0; i < 6; i++) blade(kit, { pos: [0, 1.45 - i * .08, -2.0 + i * .75], rot: [-.65, 0, 0], len: 1.15 - i * .1, w: .75, th: .02, tip: .15, belly: .3, sweep: .2, cols: [C.VOID, T, TL] });
    for (const s of [-1, 1]) horn(kit, [[s * .45, 1.6, -2.5], [s * .65, 1.8, -2.38], [s * .85, 1.95, -2.2], [s * 1.0, 2.1, -1.7]], .13, C.BONE, 12);
  });
  rig('dreadmaw', { hip: 2.2, hitbox: [3.6, 4.2, 7.8], gait: 'quad', core: 'CreatureDreadmaw', stride: 2.6, breath: .07,
    segs: [
      { shape: 'ClawLeg', at: [-.9, -.35, -1.5], role: 'legA', k: [1.8, 1.9, 1.8] }, { shape: 'ClawLeg', at: [.9, -.35, -1.5], role: 'legB', k: [1.8, 1.9, 1.8] },
      { shape: 'ClawLeg', at: [-.85, -.35, 1.6], role: 'legB', k: [1.7, 1.9, 1.7] }, { shape: 'ClawLeg', at: [.85, -.35, 1.6], role: 'legA', k: [1.7, 1.9, 1.7] },
      { shape: 'ScaleTail', at: [0, .7, 2.6], rot: [-.35, 0, 0], role: 'tail', k: 2.4 }],
    glow: glowEyes(.48, 1.3, -3.75, .13, 'C77DFF').concat([{ kind: 'core', at: [0, .5, -3.1], r: .32, color: 'C77DFF' }]),
    anchors: { crown: [0, 1.85, -2.5], shoulder: [1.1, 1.1, -1.5], chest: [0, .3, -2.5], ring: 3.6 } });

  // Fallback slime (any unknown body): a glossy blob with a face.
  creature('CreatureBlob', { smooth: ORG, tint: '88C0A8', kind: 'creature' }, kit => {
    ell(kit, 0, -.45, 0, 1.5, 1.35, 1.5, [T, T, TD], 3, { squash: .75 });
    ell(kit, .55, .3, -.75, .32, .2, .2, C.GLINT, 2);
    eyes(kit, .45, -.1, -1.25, .17, C.GLINT);
    along(kit, [0, -.6, -1.38], [[.22, -.02], [.25, 0], [.22, .02]], { n: 14, sz: .4, color: C.SOCKET, capStart: true, capEnd: true });
  });
  rig('blob', { hip: 1.5, hitbox: [3, 3, 3], gait: 'hop', core: 'CreatureBlob', stride: 1.2, breath: .1,
    segs: [], glow: glowEyes(.45, -.1, -1.25, .17, 'FFE680'), anchors: { crown: [0, .9, 0], chest: [0, -.4, -1.4], ring: 1.8 } });

  // Pet companions -----------------------------------------------------------
  creature('PetFlyer', { smooth: ORG, tint: 'F2C14E', kind: 'pet' }, kit => {
    ell(kit, 0, 0, 0, .5, .46, .62, [TD, T, C.FUR], 2);
    ell(kit, 0, .5, -.45, .38, .36, .38, [TD, T, C.FUR], 2);
    kit.group({ pos: [0, .44, -.82], rot: [-PI / 2 + .3, 0, 0] }, () => kit.lathe([[.1, 0], [.09, .06], [.06, .13], [0, .2]], { n: 12, color: C.GOLD, capStart: true }));
    eyes(kit, .17, .58, -.74, .07, C.GLINT);
    for (let i = -1; i <= 1; i++) blade(kit, { pos: [i * .1, .05, .55], rot: [PI / 2 - .3, i * .3, 0], len: .45, w: .12, th: .02, cols: [T, TL] });
    for (let i = 0; i < 2; i++) blade(kit, { pos: [0, .82, -.42 + i * .1], rot: [-.4 - i * .3, 0, 0], len: .25 - i * .06, w: .1, th: .02, cols: [TL] });
  });
  creature('PetQuad', { smooth: ORG, tint: 'C98D4F', kind: 'pet' }, kit => {
    along(kit, [0, 0, 0], [[0, -.8], [.2, -.77], [.32, -.68], [.4, -.48], [.42, -.2], [.42, .15], [.39, .45], [.32, .65], [.2, .78]], { n: 16, sz: .95, color: dorsal(TD, T, C.FUR) });
    ell(kit, 0, .42, -.82, .36, .32, .34, [TD, T, C.FUR], 2);
    along(kit, [0, .32, -1.05], [[.18, 0], [.17, .1], [.13, .2], [.06, .26], [0, .28]], { n: 12, color: C.FUR }, -.1);
    ell(kit, 0, .36, -1.33, .05, .04, .03, C.SOCKET, 1);
    eyes(kit, .15, .5, -1.08, .06, C.GLINT);
    for (const s of [-1, 1]) kit.group({ pos: [s * .2, .7, -.8], rot: [0, 0, s * -.25] }, () => kit.lathe([[.1, 0], [.095, .08], [.075, .17], [.04, .25], [0, .3]], { n: 12, sz: .5, color: bands(TD, T, T, TL), capStart: true }));
  });
  creature('PetShell', { smooth: ORG, tint: '6BAF5A', kind: 'pet' }, kit => {
    kit.lathe([[.72, -.12], [.77, -.04], [.78, .05], [.74, .18], [.66, .3], [.54, .41], [.4, .5], [.22, .56], [0, .58]], { n: 22, sz: .95, color: bands(C.GOLD, C.GOLD, TD, T, TD, T, TD, TL) });
    kit.lathe([[.7, -.25], [.71, -.18], [.72, -.12]], { n: 22, sz: .95, color: C.FUR, capStart: true, capColor: C.FUR });
    for (let i = 0; i < 6; i++) { const a = i * PI / 3; along(kit, [Math.cos(a) * .4, .45, Math.sin(a) * .38], [[.12, 0], [.1, .025], [0, .04]], { n: 12, color: TL, capStart: true }, -PI / 2 - .5) }
    ell(kit, 0, .02, -.88, .26, .24, .3, [T, T, C.FUR], 2);
    eyes(kit, .13, .1, -1.1, .055, C.GLINT);
  });
  creature('PetHopper', { smooth: ORG, tint: '8EF0F8', kind: 'pet' }, kit => {
    ell(kit, 0, 0, 0, .56, .5, .56, [T, T, C.FUR], 2, { squash: .85 });
    ell(kit, 0, -.12, -.28, .38, .32, .28, C.FUR, 2);
    for (const s of [-1, 1]) { ell(kit, s * .35, -.42, -.05, .2, .1, .3, TD, 1); ell(kit, s * .42, .08, -.24, .1, .1, .08, C.CORAL, 1) }
    eyes(kit, .24, .38, -.4, .1, C.GLINT);
    for (const s of [-1, 1]) kit.group({ pos: [s * .2, .45, .05], rot: [-.35, 0, s * -.2] }, () => kit.lathe([[.09, 0], [.1, .12], [.1, .25], [.08, .36], [.05, .45], [0, .5]], { n: 12, sz: .5, color: bands(T, T, T, TL, TL), capStart: true }));
  });
  creature('PetFloat', { smooth: ORG, tint: '9583B9', kind: 'pet' }, kit => {
    kit.lathe([[0, -.55], [.22, -.5], [.38, -.38], [.5, -.18], [.52, .02], [.46, .25], [.34, .42], [.22, .55], [.12, .68], [.05, .78], [0, .82]], { n: 16, color: bands(TD, TD, T, T, T, T, TL, TL, TL, TL), wobble: (l) => [0, l >= 6 ? (l - 5) * .05 : 0] });
    torus(kit, { rot: [.3, 0, 0], R: .7, r: .035, color: C.GOLD });
    for (let i = 0; i < 3; i++) ell(kit, 0, -.55 - i * .2, .15 + i * .2, .14 - i * .03, .14 - i * .03, .14 - i * .03, T, 1);
    eyes(kit, .14, .05, -.44, .06, C.GLINT);
  });
  const petRig = (core, gait, segs, glow, anchors, yaw = PI) => ({ hip: gait === 'float' ? 1.2 : .5, hitbox: [1.2, 1.2, 1.6], gait, core, stride: .9, breath: .06, yaw, segs, glow, anchors });
  rig('pet_flyer', petRig('PetFlyer', 'fly', [{ shape: 'FeatherWing', at: [.4, .15, -.05], role: 'wing', k: .75 }, { shape: 'FeatherWing', at: [-.4, .15, -.05], role: 'wing', mirror: 'roll', k: .75 }],
    glowEyes(.17, .58, -.74, .07, '10141A'), { crown: [0, .9, -.45] }));
  rig('pet_quad', petRig('PetQuad', 'quad', [
    { shape: 'PawLeg', at: [-.24, -.2, -.45], role: 'legA', k: .42 }, { shape: 'PawLeg', at: [.24, -.2, -.45], role: 'legB', k: .42 },
    { shape: 'PawLeg', at: [-.24, -.2, .45], role: 'legB', k: .42 }, { shape: 'PawLeg', at: [.24, -.2, .45], role: 'legA', k: .42 },
    { shape: 'FurTail', at: [0, .2, .75], role: 'tail', k: .7 }], glowEyes(.15, .5, -1.08, .06, '10141A'), { crown: [0, .78, -.8] }));
  rig('pet_shell', petRig('PetShell', 'quad', [
    { shape: 'ClawLeg', at: [-.5, -.05, -.4], rot: [0, 0, -.4], role: 'legA', k: .36 }, { shape: 'ClawLeg', at: [.5, -.05, -.4], rot: [0, 0, .4], role: 'legB', k: .36 },
    { shape: 'ClawLeg', at: [-.5, -.05, .4], rot: [0, 0, -.4], role: 'legB', k: .36 }, { shape: 'ClawLeg', at: [.5, -.05, .4], rot: [0, 0, .4], role: 'legA', k: .36 }],
    glowEyes(.13, .1, -1.1, .055, '10141A'), { crown: [0, .62, 0] }));
  rig('pet_hopper', petRig('PetHopper', 'hop', [], glowEyes(.24, .38, -.4, .1, '10141A'), { crown: [0, .75, 0] }));
  rig('pet_float', petRig('PetFloat', 'float', [0, 1, 2].map(i => ({ shape: 'WispShard', at: [Math.cos(i * 2.1) * .85, .1, Math.sin(i * 2.1) * .85], role: 'orbit', k: .35, phase: i * 2.1 })),
    [{ kind: 'core', at: [0, 0, 0], r: .22, color: 'FFFFFF' }], { crown: [0, .85, 0] }));

  return { rigs };
};
