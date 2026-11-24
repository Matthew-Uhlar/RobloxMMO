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
// (crease 40-55 degrees): no boxes stand in for bodies. Dark sockets mark the
// eyes; the client seats small Neon glow balls in them (glow list), so eyes,
// cores and rune seams bloom. Region palettes come from the tint (the
// creature's AetherData colour): backs take the dark tint, bellies the light
// one, horns / claws / bone and glass stay fixed.
'use strict';
module.exports = ({ creature, C, PI, hash }) => {
  const { TINT: T, TINT_DARK: TD, TINT_LIGHT: TL } = C;
  const rigs = {};
  const ORG = 52, HARD = 38;

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------
  // Lathe laid along -Z (profile t grows toward the nose). sx widens, sz raises.
  const along = (kit, pos, profile, opts, pitch = 0, yaw = 0) =>
    kit.group({ pos, rot: [-PI / 2 + pitch, yaw, 0] }, () => kit.lathe(profile, opts));
  // Shade a lathe laid along Z by the quad's angle: back dark, belly light.
  const dorsal = (n, top = TD, side = T, belly = TL, phase = 0) => (level, i) => {
    const s = Math.sin(phase + (i + .5) * 2 * PI / n);
    return s > .45 ? top : s < -.5 ? belly : side;
  };
  // Countershaded ellipsoid colour by face normal.
  const shade = (top = TD, side = T, belly = TL) => n => n[1] > .5 ? top : n[1] < -.45 ? belly : side;
  const ell = (kit, x, y, z, rx, ry, rz, color = shade(), sub = 2, extra = {}) =>
    kit.blob(x, y, z, rx, ry, rz, { sub, color: typeof color === 'function' ? color : () => color, ...extra });
  // Tapered horn / spike along a polyline (radius falls to a point).
  const horn = (kit, pts, r, color = C.HORN, n = 7) => {
    const m = pts.length;
    kit.tube(pts, i => Math.max(.022, r * (1 - i / (m - 1)) ** .9 + (i === m - 1 ? .02 : 0)), { n, color });
  };
  // Eye: a dark socket and a glassy iris; the client adds the Neon glow.
  const eye = (kit, x, y, z, r, iris = C.GLINT) => {
    ell(kit, x, y, z, r * 1.25, r, r * .9, C.SOCKET, 1);
    kit.jewel(x, y, z - r * .72, r * .55, r * .55, r * .3, iris);
  };
  const eyes = (kit, x, y, z, r, iris) => { eye(kit, -x, y, z, r, iris); eye(kit, x, y, z, r, iris) };
  const glowEyes = (x, y, z, r, color) => [{ kind: 'eye', at: [-x, y, z - r * .55], r: r * .62, color }, { kind: 'eye', at: [x, y, z - r * .55], r: r * .62, color }];
  // A ridge of leaf-shaped plates / spines along the back (x = 0).
  const spines = (kit, list, color = TL, depth = .14) => {
    for (const [y, z, h, l, lean] of list)
      kit.group({ pos: [0, y, z], rot: [lean ?? -.35, PI / 2, 0] }, () =>
        kit.prism([[-l / 2, 0], [-l * .2, h * .55], [l * .05, h], [l * .25, h * .5], [l / 2, 0]], depth, color, color));
  };
  const rig = (kind, spec) => { rigs[kind] = spec; };

  // -------------------------------------------------------------------------
  // Shared limbs. Legs: hip joint at the origin, foot sole at y = -1. Arms:
  // shoulder at the origin, hanging down -Y. Wings / fins: root at the origin,
  // span along +X to 1, chord along Z, flat about y = 0. Tails: base at the
  // origin, running back along +Z to 1. Orbit shards: centred on the origin.
  // -------------------------------------------------------------------------
  // Hoofed leg: muscled thigh, slim cannon, horn hoof with a fetlock tuft.
  creature('HoofLeg', { smooth: ORG, tint: 'A0683D', kind: 'limb' }, kit => {
    kit.tube([[0, .05, 0], [0, -.2, .04], [0, -.42, .02], [0, -.62, -.03], [0, -.8, 0]], [.25, .22, .15, .1, .095], { n: 10, color: (i, k) => i < 1 ? TD : T });
    ell(kit, 0, -.78, -.02, .13, .07, .14, TL, 1);
    kit.lathe([[.13, -1], [.135, -.93], [.115, -.86], [.085, -.81]], { n: 10, capStart: true, capEnd: true, color: C.HORN, capColor: C.CLAW });
    kit.box(0, -.96, -.13, .02, .08, .06, C.CLAW);
  });
  // Paw leg (digitigrade): thigh, hock bend, padded paw with three toes.
  creature('PawLeg', { smooth: ORG, tint: '8A6A4A', kind: 'limb' }, kit => {
    kit.tube([[0, .05, 0], [0, -.25, -.08], [0, -.5, .06], [0, -.75, .1], [0, -.9, .02]], [.22, .19, .12, .095, .09], { n: 10, color: (i) => i < 1 ? TD : T });
    ell(kit, 0, -.93, -.07, .13, .075, .17, T, 1);
    for (const x of [-.07, 0, .07]) { ell(kit, x, -.95, -.21, .045, .045, .05, TL, 1); kit.lathe([[.018, 0], [0, .07]], { n: 5, capStart: true, color: C.CLAW }) }
    for (const x of [-.07, 0, .07]) kit.group({ pos: [x, -.97, -.25], rot: [-1.2, 0, 0] }, () => kit.lathe([[.02, 0], [.012, .05], [0, .09]], { n: 5, capStart: true, color: C.CLAW }));
  });
  // Clawed leg (reptile / hound): scaled thigh, armoured shin, splayed claws.
  creature('ClawLeg', { smooth: 46, tint: '5E7C68', kind: 'limb' }, kit => {
    kit.tube([[0, .06, 0], [0, -.22, -.12], [0, -.48, -.04], [0, -.72, .06], [0, -.9, 0]], [.26, .22, .14, .12, .1], { n: 10, color: (i, k) => (k + i) % 4 === 0 ? TD : T });
    for (const [y, z] of [[-.5, -.13], [-.66, -.08]]) kit.group({ pos: [0, y, z], rot: [.25, 0, 0] }, () => kit.lathe([[.12, -.06], [.135, 0], [.1, .07]], { n: 8, color: TL, capEnd: true }));
    ell(kit, 0, -.93, -.06, .15, .07, .18, TD, 1);
    for (const a of [-.45, 0, .45]) kit.group({ pos: [Math.sin(a) * .1, -.96, -.18], rot: [-1.35, a, 0] }, () => horn(kit, [[0, 0, 0], [0, .08, 0], [0, .16, -.03]], .04, C.CLAW, 5));
    horn(kit, [[0, -.5, .12], [0, -.42, .24], [0, -.3, .3]], .045, C.HORN, 5);
  });
  // Arthropod leg: coxa out along +X, femur up and out, tibia down to a claw.
  creature('ChitinLeg', { smooth: 34, tint: '6B5240', kind: 'limb' }, kit => {
    kit.tube([[0, 0, 0], [.25, .12, 0], [.5, .3, 0], [.66, .32, 0]], [.11, .1, .085, .08], { n: 8, color: (i, k) => k < 3 ? TD : T });
    ell(kit, .66, .32, 0, .1, .1, .1, TL, 1);
    kit.tube([[.66, .32, 0], [.82, .05, 0], [.92, -.35, 0], [.95, -.62, 0]], [.08, .07, .05, .03], { n: 8, color: (i, k) => k < 3 ? TD : T });
    horn(kit, [[.95, -.6, 0], [.96, -.75, 0], [.95, -.86, 0]], .035, C.CLAW, 5);
    for (const t of [.3, .55]) horn(kit, [[.55 + t * .4, .3 - t * .9, 0], [.62 + t * .4, .32 - t * .9, 0], [.68 + t * .4, .36 - t * .9, 0]], .02, C.HORN, 4);
  });
  // Spider leg: tall knee arch, banded segments, hooked tip.
  creature('SpiderLeg', { smooth: 34, tint: '3F3550', kind: 'limb' }, kit => {
    kit.tube([[0, 0, 0], [.2, .2, 0], [.42, .42, 0], [.58, .48, 0]], [.1, .09, .075, .07], { n: 8, color: (i, k) => i === 1 ? TL : T });
    ell(kit, .58, .48, 0, .085, .085, .085, TD, 1);
    kit.tube([[.58, .48, 0], [.72, .25, 0], [.86, -.1, 0], [.95, -.4, 0], [.98, -.6, 0]], [.07, .06, .05, .035, .025], { n: 8, color: (i, k) => i === 2 ? TL : TD });
    horn(kit, [[.98, -.58, 0], [.99, -.72, 0], [.96, -.84, 0]], .026, C.CLAW, 5);
    for (let s = 0; s < 4; s++) kit.jewel(.25 + s * .2, .26 + (s < 2 ? s * .2 : .45 - (s - 2) * .4), 0, .02, .05, .02, C.HORN);
  });
  // Root leg (plants): a twisting root that splits into rootlets at the tip.
  creature('RootLeg', { smooth: ORG, tint: '5B4636', kind: 'limb' }, kit => {
    kit.tube([[0, 0, 0], [.18, -.2, .05], [.4, -.48, -.04], [.55, -.8, .02], [.6, -.97, 0]], [.16, .13, .1, .075, .05], { n: 9, color: (i, k) => (k + i) % 3 === 0 ? C.BARK_DARK : C.BARK, jitter: (i, k) => 1 + (hash(i, k, 71) - .5) * .25 });
    for (const a of [-.6, .6]) kit.group({ pos: [.5, -.72, 0], rot: [0, a, -.4] }, () => horn(kit, [[0, 0, 0], [.08, -.14, 0], [.12, -.27, 0]], .04, C.BARK_DARK, 5));
    for (const [x, y, z] of [[.15, -.18, .1], [.38, -.46, -.1]]) kit.group({ pos: [x, y, z], rot: [0, 0, .6] }, () => kit.prism([[0, 0], [.07, .05], [.13, 0], [.07, -.04]], .02, C.LEAF, C.LEAF));
  });
  // Vine arm (thornling): a coiling vine with thorns and a leaf tip.
  creature('VineArm', { smooth: ORG, tint: '6BAF5A', kind: 'limb' }, kit => {
    kit.tube([[0, 0, 0], [.05, -.2, -.05], [.02, -.45, -.12], [.08, -.7, -.08], [.02, -.9, 0]], [.1, .085, .07, .055, .035], { n: 9, color: (i, k) => k === 0 ? TD : T });
    for (const t of [.2, .4, .6, .78]) horn(kit, [[.05, -t * 1.05, -.06], [.12, -t * 1.05 + .02, -.1], [.19, -t * 1.05 + .05, -.13]], .03, C.BONE, 4);
    kit.group({ pos: [.02, -.92, 0], rot: [0, 0, PI] }, () => kit.prism([[0, 0], [.1, .1], [.06, .25], [0, .34], [-.06, .25], [-.1, .1]], .04, TL, T));
  });
  // Bushy tail (fur): fluffy tapered lathe with a pale tip.
  creature('FurTail', { smooth: ORG, tint: 'C98D4F', kind: 'limb' }, kit => {
    kit.group({ rot: [PI / 2 - .35, 0, 0] }, () => kit.lathe([[.06, 0], [.17, .18], [.22, .42], [.2, .7], [.14, .88], [0, 1]], {
      n: 12, color: level => level >= 4 ? C.FUR : level === 0 ? TD : T, jitter: (l, i) => l > 0 && l < 5 ? 1 + (hash(l, i, 91) - .5) * .22 : 1 }));
  });
  // Scaled tail: segmented, tapering, with a dorsal spine row and a barb.
  creature('ScaleTail', { smooth: 44, tint: '5E7C68', kind: 'limb' }, kit => {
    kit.group({ rot: [PI / 2, 0, 0] }, () => kit.lathe([[.2, 0], [.19, .15], [.16, .35], [.12, .55], [.08, .75], [.05, .9], [0, 1]], {
      n: 12, sx: 1, sz: .9, color: dorsal(12, TD, T, TL, -PI / 2), jitter: (l, i) => l > 0 && l < 6 ? (l % 2 ? 1.04 : .97) : 1 }));
    for (let s = 0; s < 5; s++) {
      const z = .1 + s * .17, r = .2 - s * .03;
      kit.group({ pos: [0, r * .82, z], rot: [-.5, PI / 2, 0] }, () => kit.prism([[-.06, 0], [0, .1 - s * .012], [.06, 0]], .025, C.HORN, C.HORN));
    }
    kit.group({ pos: [0, 0, .98], rot: [PI / 2, 0, 0] }, () => kit.lathe([[.05, 0], [.09, .06], [.03, .18], [0, .24]], { n: 6, sx: .4, color: C.HORN, capStart: true }));
  });
  // Fish tail: tapering body section and a forked fluke (sways in yaw).
  creature('FishTail', { smooth: ORG, tint: '4F8FBF', kind: 'limb' }, kit => {
    kit.group({ rot: [PI / 2, 0, 0] }, () => kit.lathe([[.42, 0], [.36, .25], [.24, .5], [.13, .68], [.09, .76]], { n: 12, sz: 1.15, color: dorsal(12, TD, T, TL, -PI / 2), capEnd: true }));
    kit.group({ pos: [0, 0, .7], rot: [0, PI / 2, 0] }, () => kit.prism([[0, -.08], [.18, -.5], [.32, -.55], [.24, -.18], [.24, .18], [.32, .55], [.18, .5], [0, .08]], .04, TL, T));
    kit.group({ pos: [0, .28, .2], rot: [0, PI / 2, 0] }, () => kit.prism([[-.15, 0], [.05, .28], [.22, .05]], .03, TL, TL));
  });
  // Feather wing: layered primaries, coverts and a brass-dark leading edge.
  creature('FeatherWing', { smooth: 30, tint: '7B8CDE', kind: 'limb' }, kit => {
    kit.tube([[0, 0, -.1], [.3, 0, -.2], [.62, 0, -.14], [.95, 0, .02]], [.07, .06, .045, .025], { n: 8, color: TD });
    kit.group({ rot: [PI / 2, 0, 0] }, () => {
      kit.prism([[0, -.24], [.3, -.28], [.6, -.22], [.85, -.1], [.62, .1], [.3, .24], [0, .2]], .05, T, TD);
      for (let f = 0; f < 7; f++) {
        const x = .28 + f * .11, l = .3 + f * .05 - (f > 4 ? (f - 4) * .09 : 0);
        kit.prism([[x - .05, .02], [x + .05, .02], [x + .07 + f * .012, l], [x + .01 + f * .012, l + .07]], .03, f % 2 ? TL : T, TD);
      }
    });
  });
  // Glass wing (sprites): two veined crystal lobes on a root knuckle.
  creature('GlassWing', { smooth: 20, tint: 'A8DADC', kind: 'limb' }, kit => {
    ell(kit, .04, 0, 0, .07, .07, .07, TL, 1);
    kit.group({ rot: [PI / 2, 0, 0] }, () => {
      kit.prism([[0, -.04], [.35, -.32], [.75, -.42], [.98, -.3], [.86, -.1], [.4, .02]], .03, C.ICE, TL);
      kit.prism([[0, .02], [.3, .12], [.58, .34], [.55, .45], [.3, .38], [.08, .14]], .03, C.ICE, TL);
    });
    for (const [a, l] of [[-.32, .85], [-.12, .7], [.35, .5]]) kit.group({ rot: [0, a, 0] }, () => kit.tube([[0, 0, 0], [l * .5, 0, 0], [l, 0, 0]], [.018, .014, .01], { n: 5, color: TL }));
  });
  // Drake wing: three finger bones, a taut membrane between them, a claw.
  creature('DrakeWing', { smooth: 28, tint: '8E7CF0', kind: 'limb' }, kit => {
    kit.tube([[0, 0, 0], [.22, .04, -.06], [.45, .06, -.1]], [.1, .085, .07], { n: 8, color: TD });
    horn(kit, [[.45, .06, -.1], [.5, .14, -.16], [.52, .2, -.22]], .05, C.CLAW, 5);
    const tips = [[1, .02, .05], [.84, .02, .42], [.6, .02, .7]];
    for (const tip of tips) kit.tube([[.45, .05, -.1], [(.45 + tip[0]) / 2, .045, (tip[2] - .1) / 2], tip], [.05, .035, .018], { n: 6, color: TD });
    kit.group({ rot: [PI / 2, 0, 0] }, () => {
      kit.prism([[0, -.04], [.45, -.12], [1, .05], [.8, .2], [.84, .42], [.66, .48], [.6, .7], [.38, .55], [.18, .46], [0, .3]], .025, T, TD);
    });
    for (const [x, z] of [[.66, .14], [.54, .38], [.32, .32]]) kit.jewel(x, 0, z, .05, .016, .05, TL);
  });
  // Ray fin: broad flat pectoral wing with a pale underside rim and spots.
  creature('RayFin', { smooth: 34, tint: '8FB8D6', kind: 'limb' }, kit => {
    // Lofted along +Z, then turned so the span runs along +X (chord along Z,
    // the trailing edge sweeping back toward +Z).
    kit.group({ rot: [0, PI / 2, 0] }, () => kit.loft([0, .2, .45, .7, .9, 1].map((x, s) => {
      const half = [.62, .58, .46, .32, .18, .06][s], th = [.12, .1, .075, .055, .035, .02][s], back = -[.0, .06, .14, .24, .34, .42][s];
      return { z: x, points: [[-half + back, 0], [-half * .4 + back, -th], [half * .5 + back, -th * .7], [half + back, 0], [half * .5 + back, th * .7], [-half * .4 + back, th]] };
    }), { color: (s, e) => e === 4 || e === 5 ? (s % 2 ? TD : T) : e <= 2 && e >= 1 ? TL : T }));
  });
  // Jelly tendril: a translucent-looking frilled ribbon hanging down -Y.
  creature('JellyTendril', { smooth: ORG, tint: 'B39DDB', kind: 'limb' }, kit => {
    const pts = [], radii = [];
    for (let s = 0; s <= 7; s++) { pts.push([Math.sin(s * .9) * .06, -s / 7, Math.cos(s * .9) * .05 - .05]); radii.push(.07 - s * .0075) }
    kit.tube(pts, radii, { n: 7, color: (i, k) => i % 2 ? TL : T });
    for (let s = 1; s < 7; s += 2) kit.jewel(pts[s][0], pts[s][1], pts[s][2] - .06, .035, .05, .02, C.GLINT);
  });
  // Wisp shard: a small faceted crystal (orbiting) with a glint.
  creature('WispShard', { smooth: 18, tint: '9583B9', kind: 'limb' }, kit => {
    kit.lathe([[0, -.5], [.16, -.2], [.2, .05], [.14, .3], [0, .55]], { n: 9, color: (l, i) => l === 1 && i % 2 ? TL : l === 0 ? TD : T, jitter: (l, i) => l > 0 && l < 4 ? 1 + (hash(l, i, 41) - .5) * .2 : 1 });
    kit.jewel(.08, .12, -.14, .03, .08, .02, C.GLINT);
  });
  // Crystal shard (sentinel / seer / sovereign orbit): long bipyramid in a
  // brass collar.
  creature('CrystalShard', { smooth: 22, tint: 'BFE4FF', kind: 'limb' }, kit => {
    kit.lathe([[0, -.5], [.15, -.18], [.18, .1], [.12, .32], [0, .5]], { n: 8, color: (l, i) => l === 2 && i % 2 ? TL : l === 0 ? TD : T });
    kit.lathe([[.19, -.04], [.21, .02], [.19, .08]], { n: 8, color: C.BRASS });
    kit.jewel(0, .02, -.2, .04, .06, .02, C.GLINT);
  });
  // Wraith arm: tattered sleeve hanging from the shoulder, a clawed hand.
  creature('WraithArm', { smooth: ORG, tint: '7FD6C8', kind: 'limb' }, kit => {
    kit.lathe([[.14, 0], [.18, -.2], [.24, -.48], [.3, -.66], [.27, -.72]], { n: 10, color: (l, i) => l >= 3 ? TL : T, jitter: (l, i) => l >= 3 ? 1 + (hash(l, i, 53) - .5) * .35 : 1,
      lift: (l, i) => l === 4 ? (hash(l, i, 54) - .5) * .12 : 0 });
    ell(kit, 0, -.62, -.04, .1, .12, .1, C.VOID, 1);
    for (const a of [-.5, 0, .5]) kit.group({ pos: [Math.sin(a) * .07, -.72, -.08], rot: [.2, a, 0] }, () => horn(kit, [[0, 0, 0], [0, -.12, -.04], [0, -.22, -.12]], .028, C.ICE, 5));
  });
  // Golem arm (metal): riveted shoulder dome, upper arm, gauntleted fist.
  creature('GolemArm', { smooth: HARD, tint: 'D4A84B', kind: 'limb' }, kit => {
    kit.lathe([[.3, -.05], [.36, .1], [.3, .26], [0, .32]], { n: 12, color: (l) => l === 1 ? C.BRASS : TD, capStart: true });
    kit.lathe([[.2, -.5], [.24, -.3], [.22, -.08]], { n: 10, color: T, capStart: true, capEnd: true });
    for (let i = 0; i < 6; i++) { const a = i * PI / 3; kit.jewel(Math.cos(a) * .35, .1, Math.sin(a) * .35, .04, .04, .04, C.BRASS) }
    ell(kit, 0, -.55, 0, .17, .14, .17, C.IRON, 1);
    kit.lathe([[.22, -1], [.26, -.92], [.27, -.72], [.22, -.58], [.18, -.55]], { n: 10, color: (l) => l === 2 ? C.BRASS : T, capStart: true, capEnd: true });
    kit.bevelBox(0, -.96, -.04, .4, .26, .4, .07, { top: TD, side: TD, bevel: C.IRON, bottom: C.IRON });
    for (const x of [-.12, 0, .12]) kit.jewel(x, -.96, -.25, .05, .05, .04, C.BRASS);
  });
  // Golem leg (metal): pistoned thigh, knee guard, broad armoured foot.
  creature('GolemLeg', { smooth: HARD, tint: 'D4A84B', kind: 'limb' }, kit => {
    kit.lathe([[.26, -.45], [.3, -.25], [.27, 0]], { n: 10, color: T, capStart: true, capEnd: true });
    ell(kit, 0, -.48, -.08, .2, .17, .2, C.IRON, 1);
    kit.group({ pos: [0, -.46, -.22], rot: [.25, 0, 0] }, () => kit.lathe([[.16, -.12], [.18, 0], [.12, .12]], { n: 8, sz: .5, color: C.BRASS, capStart: true, capEnd: true }));
    kit.lathe([[.21, -.86], [.24, -.65], [.2, -.5]], { n: 10, color: TD, capEnd: true });
    kit.bevelBox(0, -.93, -.08, .5, .14, .66, .05, { top: T, side: TD, bevel: C.BRASS, bottom: C.IRON });
  });
  // Stone arm (marble / crag): carved shoulder block, banded forearm, fist.
  creature('StoneArm', { smooth: HARD, tint: '5FA8D3', kind: 'limb' }, kit => {
    ell(kit, 0, .02, 0, .34, .3, .32, shade(TL, T, TD), 2, { seed: 7, amount: .06 });
    kit.lathe([[.2, -.55], [.23, -.35], [.24, -.15], [.2, 0]], { n: 10, color: T, capStart: true, jitter: (l, i) => 1 + (hash(l, i, 17) - .5) * .1 });
    kit.lathe([[.22, -.62], [.25, -.58], [.25, -.52], [.22, -.48]], { n: 10, color: C.BRASS });
    kit.lathe([[.2, -.85], [.24, -.7], [.21, -.55]], { n: 10, color: TL });
    ell(kit, 0, -.94, -.02, .23, .2, .22, shade(T, TD, TD), 2, { seed: 9, amount: .08 });
    kit.group({ pos: [0, -.25, -.22], rot: [0, 0, 0] }, () => kit.prism([[-.06, -.1], [.06, -.1], [.04, .12], [-.04, .12]], .02, C.RUNE, C.RUNE));
  });
  // Stone leg: tapered column, kneecap, plinth foot.
  creature('StoneLeg', { smooth: HARD, tint: '5FA8D3', kind: 'limb' }, kit => {
    kit.lathe([[.24, -.5], [.29, -.3], [.3, -.1], [.26, .02]], { n: 10, color: T, capEnd: true, jitter: (l, i) => 1 + (hash(l, i, 23) - .5) * .08 });
    ell(kit, 0, -.52, -.06, .22, .18, .22, TL, 1, { seed: 3, amount: .05 });
    kit.lathe([[.27, -.88], [.25, -.7], [.21, -.55]], { n: 10, color: TD });
    kit.lathe([[.34, -1], [.36, -.94], [.3, -.88], [.26, -.86]], { n: 10, color: (l) => l === 0 ? C.STONE_DARK : TL, capStart: true, capEnd: true, sz: 1.15 });
  });
  // Sovereign sword arm: a stone arm gripping a long glass-and-gold blade.
  creature('SovereignArm', { smooth: HARD, tint: 'F0D9A0', kind: 'limb' }, kit => {
    ell(kit, 0, .02, 0, .34, .3, .32, shade(TL, T, TD), 2, { seed: 11, amount: .05 });
    kit.lathe([[.2, -.6], [.24, -.3], [.21, 0]], { n: 10, color: T, capStart: true });
    kit.lathe([[.23, -.68], [.26, -.62], [.23, -.56]], { n: 10, color: C.GOLD });
    ell(kit, 0, -.88, -.04, .22, .2, .22, TD, 2);
    kit.group({ pos: [0, -.9, -.12], rot: [.3, 0, 0] }, () => { // the blade held upright, resting back
      kit.lathe([[.06, -.35], [.07, -.05], [.06, .05]], { n: 8, color: C.HORN, capStart: true });
      kit.bevelBox(0, .1, 0, .7, .1, .16, .04, { top: C.GOLD, side: C.GOLD, bevel: C.BRASS });
      kit.jewel(0, .1, -.1, .08, .08, .04, C.RUNE);
      kit.prism([[-.1, .15], [.1, .15], [.12, .9], [.08, 1.85], [0, 2.15], [-.08, 1.85], [-.12, .9]], .07, C.GLASS, C.GOLD);
      kit.box(0, 1.1, -.04, .03, 1.6, .02, C.GLINT);
    });
  });
  // Serpent coil: one barrel-shaped body section with a glass fin (chained).
  creature('SerpentCoil', { smooth: ORG, tint: '3FB8AF', kind: 'limb' }, kit => {
    along(kit, [0, 0, .5], [[.62, -.5], [.72, -.25], [.74, 0], [.7, .25], [.6, .5]], { n: 14, sz: 1.05, color: (l, i) => { const s = Math.sin((i + .5) * 2 * PI / 14); return s > .5 ? TD : s < -.55 ? TL : (l % 2 ? T : TD) } });
    kit.group({ pos: [0, .7, .5], rot: [0, PI / 2, 0] }, () => kit.prism([[-.42, 0], [-.18, .3], [.18, .34], [.42, 0]], .05, C.GLASS, TL));
    for (const s of [-1, 1]) kit.group({ pos: [s * .66, -.25, .5], rot: [0, 0, s * .6] }, () => kit.lathe([[.08, 0], [.05, .12], [0, .2]], { n: 6, color: TL, capStart: true }));
  });
  // Serpent tail: tapering last coils and a broad fluke.
  creature('SerpentTail', { smooth: ORG, tint: '3FB8AF', kind: 'limb' }, kit => {
    along(kit, [0, 0, 0], [[0, -1.5], [.12, -1.42], [.28, -1.1], [.42, -.6], [.5, 0]], { n: 12, color: dorsal(12) }, 0, PI);
    kit.group({ pos: [0, 0, 1.42], rot: [0, PI / 2, 0] }, () => kit.prism([[0, -.08], [.25, -.6], [.42, -.5], [.3, 0], [.42, .5], [.25, .6], [0, .08]], .05, TL, T));
    kit.group({ pos: [0, .42, .5], rot: [0, PI / 2, 0] }, () => kit.prism([[-.3, 0], [0, .28], [.5, 0]], .04, C.GLASS, TL));
  });
  // Crab claw: armoured arm and a toothed pincer (upper and lower jaw alike).
  creature('CrabClaw', { smooth: HARD, tint: 'D9774B', kind: 'limb' }, kit => {
    kit.tube([[0, 0, 0], [.25, 0, -.12], [.45, 0, -.32]], [.13, .12, .11], { n: 9, color: T });
    ell(kit, .5, 0, -.52, .26, .2, .3, shade(T, T, TL), 2);
    for (const s of [-1, 1]) {
      kit.tube([[.52, s * .06, -.78], [.56, s * .1, -.98], [.52, s * .06, -1.15]], [.11, .08, .03], { n: 8, color: s > 0 ? TD : T });
      for (const t of [.85, .97, 1.07]) kit.jewel(.54, s * .02, -t, .03, .04, .03, C.BONE);
    }
    for (const [y, z] of [[.18, -.45], [.15, -.65]]) kit.jewel(.5, y, z, .05, .04, .05, TL);
  });
  // Orbiting accents and tier overlays ---------------------------------------
  // Boss crown: a spiked brass circlet with gem sockets (seated on the head).
  creature('OverlayCrown', { smooth: HARD, tint: 'FF3B3B', kind: 'overlay' }, kit => {
    kit.lathe([[.5, 0], [.54, .06], [.54, .16], [.5, .22]], { n: 20, color: (l) => l === 1 ? C.GOLD : C.BRASS });
    kit.lathe([[.44, .22], [.48, .16], [.48, .06], [.44, 0]], { n: 20, color: C.IRON });
    for (let i = 0; i < 8; i++) {
      const a = i * PI / 4, big = i % 2 === 0, r = .5;
      kit.group({ pos: [Math.cos(a) * r, .18, Math.sin(a) * r], rot: [0, PI / 2 - a, 0] }, () => {
        kit.prism([[-.1, 0], [-.05, big ? .3 : .18], [0, big ? .5 : .28], [.05, big ? .3 : .18], [.1, 0]], .06, C.GOLD, C.BRASS);
        if (big) kit.jewel(0, .14, -.04, .06, .08, .03, T);
      });
    }
  });
  // World boss crown: a tall double crown with a floating halo band.
  creature('OverlayWorldCrown', { smooth: HARD, tint: 'FFD166', kind: 'overlay' }, kit => {
    kit.lathe([[.5, 0], [.56, .08], [.56, .22], [.52, .3]], { n: 24, color: (l) => l === 1 ? C.GOLD : C.BRASS });
    kit.lathe([[.44, .3], [.5, .2], [.5, .06], [.44, 0]], { n: 24, color: C.INK });
    for (let i = 0; i < 12; i++) {
      const a = i * PI / 6, h = i % 3 === 0 ? .85 : i % 3 === 1 ? .5 : .62;
      kit.group({ pos: [Math.cos(a) * .52, .26, Math.sin(a) * .52], rot: [0, PI / 2 - a, 0] }, () => {
        kit.prism([[-.08, 0], [-.04, h * .6], [0, h], [.04, h * .6], [.08, 0]], .06, C.GOLD, C.BRASS);
        if (i % 3 === 0) kit.jewel(0, h * .45, -.04, .06, .1, .03, T);
      });
    }
    kit.ring(.68, .05, .04, TL, 32, PI / 2, 0, PI * 2, 1.15);
    kit.ring(.62, .03, .05, C.GOLD, 32, PI / 2, 0, PI * 2, 1.15);
    for (let i = 0; i < 6; i++) { const a = i * PI / 3 + PI / 6; kit.jewel(Math.cos(a) * .66, 1.15, Math.sin(a) * .66, .05, .09, .05, T) }
  });
  // Armour pauldron (brute and up): layered plates with a rim and a spike.
  creature('OverlayPauldron', { smooth: HARD, tint: 'B0B8C4', kind: 'overlay' }, kit => {
    for (let k = 0; k < 3; k++) {
      kit.group({ pos: [k * .08, -k * .12, 0], rot: [0, 0, -.35 - k * .15] }, () =>
        kit.lathe([[.42 - k * .06, -.04], [.44 - k * .06, .02], [.36 - k * .06, .14], [.2 - k * .04, .22], [0, .25]], {
          n: 14, sz: .9, color: (l) => l === 0 ? C.BRASS : k === 0 ? T : TD, capStart: true }));
    }
    horn(kit, [[.05, .2, 0], [.12, .42, 0], [.16, .6, .02]], .07, C.BONE, 6);
    for (let i = 0; i < 5; i++) { const a = i * .55 - 1.1; kit.jewel(Math.sin(a) * .38, -.02, Math.cos(a) * .38 * .9, .03, .03, .03, C.BRASS) }
  });
  // Elite horns: a swept pair joined by a bone brow plate.
  creature('OverlayHorns', { smooth: HARD, tint: 'EDE2C4', kind: 'overlay' }, kit => {
    for (const s of [-1, 1]) horn(kit, [[s * .18, 0, 0], [s * .38, .12, .06], [s * .52, .34, .16], [s * .54, .58, .32], [s * .46, .74, .46]], .12, C.BONE, 8);
    kit.loft([{ z: -.06, points: [[-.3, -.03], [0, .05], [.3, -.03], [0, -.08]] }, { z: .06, points: [[-.32, -.03], [0, .07], [.32, -.03], [0, -.08]] }], { color: C.HORN });
    for (const s of [-1, 1]) for (const t of [.25, .5]) kit.lathe([[.135 - t * .06, -.012 + s * 0], [.14 - t * .06, .012]], { n: 8, color: C.HORN });
  });
  // Rune ring: the ground circle under a boss (stance-tinted by the client).
  creature('OverlayRuneRing', { smooth: 0, tint: 'FF3B3B', kind: 'overlay' }, kit => {
    kit.ring(1, .06, .03, T, 40, PI / 2, 0, PI * 2, .015);
    kit.ring(.82, .03, .03, TD, 40, PI / 2, 0, PI * 2, .015);
    for (let i = 0; i < 12; i++) {
      const a = i * PI / 6;
      kit.group({ pos: [Math.cos(a) * .91, .016, Math.sin(a) * .91], rot: [0, PI / 2 - a, 0] }, () => kit.box(0, 0, 0, i % 2 ? .05 : .1, .03, .09, TL));
    }
  });

  // -------------------------------------------------------------------------
  // Cores (one per body kind) and their rigs.
  // -------------------------------------------------------------------------
  // Brambleback Boar (hip 1.9): a barrel-bodied boar with a bramble mane.
  creature('CreatureBoar', { smooth: ORG, tint: 'A0683D', kind: 'creature' }, kit => {
    along(kit, [0, .1, 0], [[0, -2.55], [.5, -2.45], [1.05, -2.05], [1.3, -1.3], [1.35, -.3], [1.3, .6], [1.15, 1.3], [.85, 1.75]], { n: 16, sx: .92, sz: 1.02, color: dorsal(16) });
    along(kit, [0, .3, -1.75], [[.75, 0], [.9, .4], [.82, .85], [.55, 1.25], [.45, 1.55], [.43, 1.75]], { n: 14, sx: .95, color: dorsal(14) }, .1);
    along(kit, [0, -.08, -3.4], [[.43, 0], [.42, .12], [.36, .17]], { n: 14, capEnd: true, capColor: TL, color: TL }, .05);
    for (const s of [-1, 1]) { ell(kit, s * .12, -.08, -3.58, .05, .07, .02, C.SOCKET, 1); horn(kit, [[s * .32, -.25, -3.2], [s * .55, -.15, -3.38], [s * .62, .12, -3.42], [s * .55, .32, -3.3]], .09, C.BONE, 7) }
    eyes(kit, .55, .62, -2.9, .15, C.AMBER);
    for (const s of [-1, 1]) kit.group({ pos: [s * .62, 1.15, -2.2], rot: [-.2, 0, s * .55] }, () => ell(kit, 0, .2, 0, .14, .3, .08, shade(TD, TD, TL), 1));
    // Bramble mane: leafy spikes with thorns along the spine.
    for (let i = 0; i < 7; i++) {
      const z = -1.9 + i * .58, y = 1.28 - Math.abs(z + .2) * .1;
      kit.group({ pos: [0, y, z], rot: [-.45, PI / 2, 0] }, () => kit.prism([[-.3, 0], [-.1, .45 - i * .03], [.05, .68 - i * .05], [.2, .35], [.32, 0]], .16, i % 2 ? C.MOSS : C.LEAF_DARK, C.LEAF_DARK));
      if (i % 2 === 0) for (const s of [-1, 1]) horn(kit, [[s * .25, y - .05, z], [s * .45, y + .1, z + .05], [s * .55, y + .25, z + .1]], .05, C.BONE, 5);
    }
    kit.group({ pos: [0, .55, 2.35], rot: [.5, 0, 0] }, () => kit.tube([[0, 0, 0], [0, .1, .2], [.08, .3, .3], [0, .42, .22]], [.09, .08, .06, .03], { n: 6, color: TD }));
  });
  rig('boar', { hip: 1.9, hitbox: [3, 3.4, 6.4], gait: 'quad', core: 'CreatureBoar', stride: 2.2, breath: .06,
    segs: [
      { shape: 'HoofLeg', at: [-.78, -.5, -1.3], role: 'legA', k: 1.42 }, { shape: 'HoofLeg', at: [.78, -.5, -1.3], role: 'legB', k: 1.42 },
      { shape: 'HoofLeg', at: [-.78, -.5, 1.3], role: 'legB', k: 1.42 }, { shape: 'HoofLeg', at: [.78, -.5, 1.3], role: 'legA', k: 1.42 }],
    glow: glowEyes(.55, .62, -2.9, .15, 'FFE680'), anchors: { crown: [0, 1.35, -2.15], shoulder: [1.05, .9, -1.35], chest: [0, .2, -2.3], ring: 2.4 } });

  // Thornling (hip 1.8): a walking flower bulb on roots, vine arms.
  creature('CreatureThornling', { smooth: ORG, tint: '8BC34A', kind: 'creature' }, kit => {
    kit.lathe([[.55, -.9], [.62, -.5], [.5, 0], [.55, .5], [.72, .95]], { n: 12, color: (l, i) => (i + l) % 3 === 0 ? TD : T, jitter: (l, i) => 1 + (hash(l, i, 5) - .5) * .12 });
    ell(kit, 0, 1.9, 0, 1.15, 1.08, 1.12, shade(T, T, TL), 2, { seed: 3, amount: .03 });
    for (let i = 0; i < 6; i++) {
      const a = i * PI / 3 + PI / 6;
      kit.group({ pos: [Math.cos(a) * .55, 2.65, Math.sin(a) * .55], rot: [0, PI / 2 - a, 0] }, () => kit.group({ rot: [-.55, 0, 0] }, () =>
        kit.prism([[-.32, 0], [-.4, .45], [-.2, .95], [0, 1.15], [.2, .95], [.4, .45], [.32, 0]], .1, C.ROSE, C.CRIMSON)));
    }
    ell(kit, 0, 3.05, 0, .38, .3, .38, C.AMBER, 1);
    for (let i = 0; i < 8; i++) { const a = i * PI / 4; kit.jewel(Math.cos(a) * .32, 3.3, Math.sin(a) * .32, .05, .14, .05, C.GOLD) }
    eyes(kit, .42, 2.05, -1.0, .17, C.GLINT);
    kit.group({ pos: [0, 1.55, -1.02], rot: [0, 0, 0] }, () => kit.lathe([[.42, -.06], [.46, 0], [.42, .06]], { n: 12, sx: 1, sz: .25, color: C.SOCKET, capStart: true, capEnd: true }));
    for (const x of [-.3, -.1, .1, .3]) kit.group({ pos: [x, 1.66, -1.08], rot: [PI, 0, 0] }, () => kit.lathe([[.04, 0], [0, .12]], { n: 5, capStart: true, color: C.BONE }));
    for (let i = 0; i < 6; i++) { const a = i * 1.7; horn(kit, [[Math.cos(a) * .55, -.4 + i * .22, Math.sin(a) * .55], [Math.cos(a) * .8, -.32 + i * .22, Math.sin(a) * .8]], .06, C.BONE, 5) }
    kit.lathe([[.85, .9], [.98, 1.05], [.7, 1.2]], { n: 12, color: C.LEAF_DARK });
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
      along(kit, [0, 0, z], [[0, -.62], [r * .7, -.55], [r, -.2], [r, .2], [r * .7, .55], [0, .62]], { n: 14, sz: h / r, color: dorsal(14, TD, T, TL) });
      kit.group({ pos: [0, .05, z], rot: [0, 0, 0] }, () => along(kit, [0, 0, 0], [[r * 1.08, -.45], [r * 1.12, 0], [r * 1.06, .42]], { n: 14, sz: h / r, color: (l, k) => { const s = Math.sin((k + .5) * 2 * PI / 14); return s > -.1 ? (k % 2 ? C.SLATE : C.STONE_LIGHT) : C.STONE } }));
      if (i < 3) spines(kit, [[h * 1.08, z + .1, .35, .5, -.6]], C.STONE_LIGHT, .1);
    });
    for (const s of [-1, 1]) horn(kit, [[s * .35, -.25, -2.3], [s * .45, -.3, -2.7], [s * .25, -.32, -3.05], [s * .05, -.3, -3.15]], .12, C.BONE, 7);
    for (const s of [-1, 1]) horn(kit, [[s * .3, .5, -2.3], [s * .55, 1.0, -2.6], [s * .9, 1.35, -2.45]], .04, TD, 5);
    eyes(kit, .42, .35, -2.42, .13, C.EMBER);
  });
  rig('crawler', { hip: 1.1, hitbox: [3.4, 2.4, 6.4], gait: 'hex', core: 'CreatureCrawler', stride: 1.4, breath: .04,
    segs: [-1.4, -.2, 1.0].flatMap((z, i) => [
      { shape: 'ChitinLeg', at: [.78, -.25, z], rot: [0, .15 - i * .15, 0], role: i % 2 ? 'legB' : 'legA', k: [1.35, 1.0, 1.35] },
      { shape: 'ChitinLeg', at: [-.78, -.25, z], rot: [0, -.15 + i * .15, 0], role: i % 2 ? 'legA' : 'legB', mirror: 'yaw', k: [1.35, 1.0, 1.35] }]),
    glow: glowEyes(.42, .35, -2.42, .13, 'FF9F43'), anchors: { crown: [0, 1.0, -1.7], shoulder: [.9, .7, -.5], chest: [0, .2, -2.2], ring: 2.6 } });

  // Cinder Mite (hip 1.3): a round ember tick with a glowing cracked abdomen.
  creature('CreatureMite', { smooth: ORG, tint: 'B5543A', kind: 'creature' }, kit => {
    ell(kit, 0, .1, .35, 1.25, 1.1, 1.3, shade(TD, T, TL), 2, { seed: 13, amount: .03 });
    ell(kit, 0, .35, 1.75, 1.0, .95, 1.0, shade(C.INK, TD, T), 2, { seed: 17, amount: .04 });
    for (let i = 0; i < 6; i++) { const a = -.9 + i * .36; kit.group({ pos: [Math.sin(a) * .98, .35 + Math.cos(a) * .9, 1.75], rot: [0, 0, -a] }, () => kit.box(0, 0, 0, .07, .04, 1.2 - Math.abs(a) * .4, C.FLAME)) }
    ell(kit, 0, -.08, -1.12, .65, .6, .58, shade(TD, TD, T), 2);
    for (const s of [-1, 1]) horn(kit, [[s * .25, -.45, -1.5], [s * .28, -.7, -1.62], [s * .15, -.82, -1.5]], .09, C.BONE, 6);
    for (let i = 0; i < 5; i++) { const a = i * .5 - 1; horn(kit, [[Math.sin(a) * .9, 1.05, .1 + i * .2], [Math.sin(a) * 1.05, 1.35, .2 + i * .2]], .08, C.HORN, 5) }
    eyes(kit, .3, .1, -1.6, .12, C.FLAME);
  });
  rig('mite', { hip: 1.3, hitbox: [3.6, 2.6, 4.4], gait: 'hex', core: 'CreatureMite', stride: 1.3, breath: .05,
    segs: [-.6, 0, .6, 1.2].flatMap((z, i) => [
      { shape: 'ChitinLeg', at: [.95, -.35, z], rot: [0, .4 - i * .27, 0], role: i % 2 ? 'legB' : 'legA', k: 1.25 },
      { shape: 'ChitinLeg', at: [-.95, -.35, z], rot: [0, -.4 + i * .27, 0], role: i % 2 ? 'legA' : 'legB', mirror: 'yaw', k: 1.25 }]),
    glow: glowEyes(.3, .1, -1.6, .12, 'FFD23F').concat([{ kind: 'rune', at: [0, 1.32, 1.75], r: .22, color: 'FF8A3D' }]),
    anchors: { crown: [0, 1.15, .2], shoulder: [1.0, .8, .1], chest: [0, .1, -1.2], ring: 2 } });

  // Bark Stalker (hip 2.7): a lean wooden wolf-stag with branch antlers.
  creature('CreatureStalker', { smooth: ORG, tint: '6E5A3E', kind: 'creature' }, kit => {
    along(kit, [0, .35, 0], [[0, -2.3], [.55, -2.15], [.95, -1.5], [1.0, -.4], [1.1, .6], [1.05, 1.4], [.75, 2.0]], { n: 14, sx: .9, color: (l, i) => (i + l) % 5 === 0 ? C.BARK_DARK : dorsal(14)(l, i), jitter: (l, i) => l > 0 ? 1 + (hash(l, i, 29) - .5) * .1 : 1 });
    kit.tube([[0, .9, -1.8], [0, 1.35, -2.4], [0, 1.6, -2.85]], [.6, .5, .45], { n: 12, color: (i, k) => k < 3 || k > 9 ? TD : T });
    along(kit, [0, 1.55, -2.65], [[.5, 0], [.52, .35], [.38, .9], [.22, 1.3], [0, 1.4]], { n: 12, sz: .82, color: dorsal(12) }, .08);
    along(kit, [0, 1.1, -2.85], [[.32, 0], [.3, .5], [.16, .95], [0, 1.05]], { n: 10, sz: .4, color: TD }, -.1);
    for (const x of [-.18, -.06, .06, .18]) kit.group({ pos: [x, 1.25, -3.6], rot: [PI, 0, 0] }, () => kit.lathe([[.03, 0], [0, .1]], { n: 5, capStart: true, color: C.BONE }));
    eyes(kit, .32, 1.72, -3.2, .12, C.MINT);
    for (const s of [-1, 1]) {
      horn(kit, [[s * .25, 2.0, -2.5], [s * .5, 2.6, -2.3], [s * .62, 3.2, -2.0], [s * .55, 3.6, -1.7]], .1, C.BARK, 7);
      horn(kit, [[s * .5, 2.6, -2.3], [s * .9, 2.85, -2.45], [s * 1.1, 3.05, -2.4]], .055, C.BARK, 5);
      horn(kit, [[s * .6, 3.15, -2.0], [s * .95, 3.35, -1.95]], .04, C.BARK, 5);
      kit.group({ pos: [s * 1.1, 3.05, -2.4], rot: [0, 0, s * .4] }, () => kit.prism([[0, 0], [.12, .1], [.08, .28], [0, .34], [-.08, .28], [-.12, .1]], .03, C.LEAF, C.MOSS));
    }
    spines(kit, [[1.4, -1.6, .6, .7], [1.45, -.8, .55, .7], [1.45, .0, .5, .7], [1.4, .8, .45, .65]], C.MOSS, .12);
  });
  rig('stalker', { hip: 2.7, hitbox: [3, 4.6, 6.4], gait: 'quad', core: 'CreatureStalker', stride: 3.2, breath: .07,
    segs: [
      { shape: 'PawLeg', at: [-.7, -.35, -1.35], role: 'legA', k: [2.0, 2.35, 2.0] }, { shape: 'PawLeg', at: [.7, -.35, -1.35], role: 'legB', k: [2.0, 2.35, 2.0] },
      { shape: 'PawLeg', at: [-.7, -.35, 1.35], role: 'legB', k: [2.0, 2.35, 2.0] }, { shape: 'PawLeg', at: [.7, -.35, 1.35], role: 'legA', k: [2.0, 2.35, 2.0] },
      { shape: 'FurTail', at: [0, .8, 2.2], role: 'tail', k: 2.0 }],
    glow: glowEyes(.32, 1.72, -3.2, .12, 'C7FF6B'), anchors: { crown: [0, 2.05, -2.55], shoulder: [.85, 1.1, -1.3], chest: [0, .4, -2.0], ring: 2.6 } });

  // Gale Sprite (hip 4, flying): a swirling wind spirit with a gust tail.
  creature('CreatureSprite', { smooth: ORG, tint: 'A8DADC', kind: 'creature' }, kit => {
    ell(kit, 0, 0, 0, .95, 1.0, .95, shade(TL, T, T), 2);
    kit.group({ rot: [-PI / 2 - .4, 0, 0] }, () => kit.lathe([[.85, 0], [.62, -.6], [.4, -1.2], [.22, -1.8], [.08, -2.3], [0, -2.6]], { n: 12, color: (l, i) => (i + l * 2) % 6 < 2 ? TL : T,
      wobble: (l, i) => [Math.sin(l * 1.2) * .18, 0], lift: () => 0 }));
    for (const [r, t, y] of [[1.15, .35, .1], [1.3, -.4, -.2], [1.0, .9, .4]]) kit.ring(r, .07, .05, TL, 24, PI / 2 + t, .3, PI * 1.4, y);
    eyes(kit, .36, .2, -.82, .14, C.NAVY);
    kit.group({ pos: [0, -.2, -.92], rot: [0, 0, 0] }, () => kit.lathe([[.12, -.02], [.14, 0], [.12, .02]], { n: 8, sz: .3, color: C.SOCKET, capStart: true, capEnd: true }));
    for (let i = 0; i < 5; i++) { const a = i * 2 * PI / 5; kit.jewel(Math.cos(a) * .55, .95, Math.sin(a) * .55, .07, .26, .07, C.ICE) }
  });
  rig('sprite', { hip: 4, hitbox: [3.2, 3.2, 3.2], gait: 'fly', core: 'CreatureSprite', flap: 9, breath: .1,
    segs: [{ shape: 'GlassWing', at: [.7, .4, .25], rot: [0, -.35, .35], role: 'wing', k: 1.6 }, { shape: 'GlassWing', at: [-.7, .4, .25], rot: [0, .35, -.35], role: 'wing', mirror: 'roll', k: 1.6 }],
    glow: glowEyes(.36, .2, -.82, .14, 'E9F5FF').concat([{ kind: 'core', at: [0, 0, 0], r: .5, color: 'F1FAEE', orbit: 0 },
      { kind: 'mote', at: [1.8, .3, 0], r: .18, color: 'F1FAEE', orbit: 1.6 }, { kind: 'mote', at: [-1.8, -.2, 0], r: .18, color: 'F1FAEE', orbit: 1.6 }]),
    anchors: { crown: [0, 1.0, 0], chest: [0, -.1, -.9], ring: 1.8 } });

  // Brass Golem (hip 3.4): riveted boiler chest, visor head, flue stacks.
  creature('CreatureGolem', { smooth: HARD, tint: 'D4A84B', kind: 'creature' }, kit => {
    kit.lathe([[1.0, -.75], [1.35, -.55], [1.6, .2], [1.7, .9], [1.55, 1.8], [1.05, 2.15]], { n: 16, sz: .75, color: (l, i) => l === 2 ? C.BRASS : (i % 4 === 0 ? TD : T) });
    for (let l = 0; l < 3; l++) for (let i = 0; i < 12; i++) { const a = i * PI / 6, y = .1 + l * .8, r = [1.6, 1.7, 1.55][l]; kit.jewel(Math.cos(a) * r * 1.01, y, Math.sin(a) * r * .76, .06, .06, .06, C.BRASS) }
    kit.group({ pos: [0, .9, -1.18], rot: [-PI / 2, 0, 0] }, () => kit.lathe([[.62, 0], [.66, .08], [.55, .16], [.42, .2]], { n: 16, color: (l) => l === 1 ? C.BRASS : C.IRON, capEnd: true, capColor: C.SOCKET }));
    kit.lathe([[1.0, -1.35], [1.1, -1.1], [1.0, -.75]], { n: 14, sz: .75, color: C.IRON, capStart: true });
    kit.group({ pos: [0, 2.45, -.1] }, () => {
      kit.bevelBox(0, .4, 0, 1.55, 1.2, 1.4, .25, { top: TD, side: T, bevel: C.BRASS, bottom: C.IRON });
      kit.bevelBox(0, .45, -.68, 1.2, .3, .12, .05, C.SOCKET);
      kit.lathe([[.15, 1.0], [.17, 1.2], [.06, 1.35], [0, 1.42]], { n: 8, color: C.BRASS });
    });
    for (const s of [-1, 1]) kit.group({ pos: [s * .8, 0, 1.05] }, () => kit.lathe([[.24, 1.8], [.26, 2.7], [.33, 2.9], [.3, 3.05]], { n: 10, color: (l) => l > 1 ? C.IRON : TD, capStart: true }));
  });
  rig('golem', { hip: 3.4, hitbox: [5.2, 7, 3], gait: 'biped', core: 'CreatureGolem', stride: 2.6, breath: .05,
    segs: [
      { shape: 'GolemLeg', at: [-.75, -1.25, 0], role: 'legA', k: [1.7, 2.15, 1.7] }, { shape: 'GolemLeg', at: [.75, -1.25, 0], role: 'legB', k: [1.7, 2.15, 1.7] },
      { shape: 'GolemArm', at: [-2.05, 1.85, 0], role: 'armB', mirror: 'yaw', k: 2.3 }, { shape: 'GolemArm', at: [2.05, 1.85, 0], role: 'armA', k: 2.3 }],
    glow: [{ kind: 'eye', at: [0, 2.9, -.98], r: .2, color: '5CE1E6', bar: [1.0, .14] }, { kind: 'core', at: [0, .9, -1.32], r: .38, color: '5CE1E6' }],
    anchors: { crown: [0, 3.95, -.1], shoulder: [2.05, 2.25, 0], chest: [0, .9, -1.4], ring: 3.2 } });

  // Storm Harrier (hip 5, flying): a sleek raptor with a glowing crest.
  creature('CreatureHarrier', { smooth: ORG, tint: '7B8CDE', kind: 'creature' }, kit => {
    along(kit, [0, 0, 0], [[0, -1.6], [.35, -1.45], [.7, -.9], [.78, -.1], [.68, .6], [.5, 1.1], [.45, 1.4]], { n: 14, sz: .95, color: dorsal(14) });
    ell(kit, 0, .38, -1.65, .55, .52, .6, shade(TD, T, TL), 2);
    kit.group({ pos: [0, .22, -2.15], rot: [-PI / 2 + .55, 0, 0] }, () => kit.lathe([[.2, 0], [.17, .2], [.1, .42], [0, .55]], { n: 8, sx: .8, color: C.GOLD, capStart: true }));
    kit.group({ pos: [0, .02, -2.45], rot: [0, 0, 0] }, () => horn(kit, [[0, .1, 0], [0, -.05, -.08], [0, -.2, -.02]], .07, C.GOLD, 6));
    eyes(kit, .35, .55, -1.95, .11, C.GLINT);
    spines(kit, [[.85, -1.55, .7, .45, -.9], [.75, -1.15, .55, .4, -1.0]], C.ICE, .08);
    for (let i = -2; i <= 2; i++) kit.group({ pos: [i * .16, .05, 1.35], rot: [PI / 2 - .1, i * .25, 0] }, () => kit.prism([[-.12, 0], [-.14, .9 - Math.abs(i) * .12], [0, 1.1 - Math.abs(i) * .12], [.14, .9 - Math.abs(i) * .12], [.12, 0]], .04, i % 2 ? TL : TD, TD));
    for (const s of [-1, 1]) {
      kit.tube([[s * .3, -.55, .2], [s * .32, -.85, .25], [s * .3, -1.05, .1]], [.1, .08, .06], { n: 6, color: C.GOLD });
      for (const a of [-.4, 0, .4]) kit.group({ pos: [s * .3, -1.05, .05], rot: [-1.0, a, 0] }, () => horn(kit, [[0, 0, 0], [0, .1, 0], [0, .16, .05]], .035, C.CLAW, 4));
    }
  });
  rig('harrier', { hip: 5, hitbox: [6, 2.4, 4.4], gait: 'fly', core: 'CreatureHarrier', flap: 5, breath: .06,
    segs: [{ shape: 'FeatherWing', at: [.6, .25, -.2], role: 'wing', k: [3.6, 2.2, 2.8] }, { shape: 'FeatherWing', at: [-.6, .25, -.2], role: 'wing', mirror: 'roll', k: [3.6, 2.2, 2.8] }],
    glow: glowEyes(.35, .55, -1.95, .11, 'E9F5FF').concat([{ kind: 'rune', at: [0, .95, -1.35], r: .16, color: 'CFE8FF' }]),
    anchors: { crown: [0, .9, -1.6], shoulder: [.6, .5, -.3], chest: [0, -.2, -1.3], ring: 3 } });

  // Gloomfang Spider (hip 1.6): bulbous abdomen with a glowing sigil, eye cluster.
  creature('CreatureSpider', { smooth: ORG, tint: '4B3F72', kind: 'creature' }, kit => {
    ell(kit, 0, .5, 1.35, 1.4, 1.25, 1.55, shade(TD, T, TL), 2, { seed: 21, amount: .02 });
    for (let i = 0; i < 4; i++) kit.ring(1.2 - i * .05, .08, .05, i % 2 ? C.INK : TL, 24, .3 + i * .35, PI * .1, PI * .8, .5);
    ell(kit, 0, .05, -.55, .9, .7, .95, shade(TD, TD, T), 2);
    ell(kit, 0, .05, -1.35, .55, .5, .5, shade(TD, TD, T), 1);
    const eyePts = [[-.3, .35, -1.72, .11], [.3, .35, -1.72, .11], [-.52, .18, -1.58, .08], [.52, .18, -1.58, .08], [-.15, .52, -1.65, .07], [.15, .52, -1.65, .07]];
    for (const [x, y, z, r] of eyePts) eye(kit, x, y, z, r, C.ROSE);
    for (const s of [-1, 1]) kit.tube([[s * .22, -.25, -1.6], [s * .28, -.6, -1.75], [s * .15, -.85, -1.6]], [.14, .1, .03], { n: 7, color: C.BONE });
    for (let i = 0; i < 6; i++) horn(kit, [[(i - 2.5) * .35, 1.55, .9 + (i % 2) * .5], [(i - 2.5) * .4, 1.85, 1.0 + (i % 2) * .5]], .06, C.HORN, 5);
  });
  rig('spider', { hip: 1.6, hitbox: [6, 3, 5.6], gait: 'octo', core: 'CreatureSpider', stride: 1.6, breath: .04,
    segs: [-1.0, -.6, -.2, .2].flatMap((z, i) => [
      { shape: 'SpiderLeg', at: [.62, .05, z], rot: [0, .55 - i * .37, 0], role: i % 2 ? 'legB' : 'legA', k: [2.4, 1.95, 2.4] },
      { shape: 'SpiderLeg', at: [-.62, .05, z], rot: [0, -.55 + i * .37, 0], role: i % 2 ? 'legA' : 'legB', mirror: 'yaw', k: [2.4, 1.95, 2.4] }]),
    glow: [[-.3, .35, -1.72, .11], [.3, .35, -1.72, .11], [-.52, .18, -1.58, .08], [.52, .18, -1.58, .08]].map(([x, y, z, r]) => ({ kind: 'eye', at: [x, y, z - r * .55], r: r * .62, color: 'D65DB1' }))
      .concat([{ kind: 'rune', at: [0, 1.78, 1.25], r: .24, color: 'B388EB' }]),
    anchors: { crown: [0, .75, -.6], shoulder: [.9, .55, -.5], chest: [0, 0, -1.4], ring: 3.2 } });

  // Void Wisp (hip 4, floating): a flame-crowned orb in a ring cage.
  creature('CreatureWisp', { smooth: ORG, tint: '6A4C93', kind: 'creature' }, kit => {
    kit.lathe([[0, -.95], [.5, -.82], [.82, -.4], [.9, .1], [.7, .55], [.45, .95], [.25, 1.45], [.1, 1.75], [0, 1.9]], { n: 14, color: (l, i) => l >= 5 ? TL : l <= 1 ? TD : T,
      wobble: (l) => [0, l >= 5 ? (l - 4) * .1 : 0] });
    for (const [t, y] of [[.35, 0], [-.35, .1], [PI / 2, -.1]]) kit.ring(1.25, .06, .06, C.INK, 28, PI / 2 + t, 0, PI * 2, y);
    for (let i = 0; i < 3; i++) kit.group({ pos: [0, -.9 - i * .5, .35 + i * .45] }, () => ell(kit, 0, 0, 0, .35 - i * .08, .35 - i * .08, .35 - i * .08, T, 1));
    eyes(kit, .28, .15, -.78, .12, C.GLINT);
  });
  rig('wisp', { hip: 4, hitbox: [3.4, 3.4, 3.4], gait: 'float', core: 'CreatureWisp', breath: .12,
    segs: [0, 1, 2, 3].map(i => ({ shape: 'WispShard', at: [Math.cos(i * PI / 2) * 1.9, (i % 2 ? .3 : -.2), Math.sin(i * PI / 2) * 1.9], role: 'orbit', k: 1.3, phase: i * PI / 2 })),
    glow: glowEyes(.28, .15, -.78, .12, 'FFFFFF').concat([{ kind: 'core', at: [0, 0, 0], r: .55, color: 'C9B6FF' }]),
    anchors: { crown: [0, 1.95, 0], chest: [0, 0, -.9], ring: 2 } });

  // Reef Lurker (hip 1.6): a toothy angler-lizard with a glowing lure.
  creature('CreatureLurker', { smooth: ORG, tint: '4F8FBF', kind: 'creature' }, kit => {
    along(kit, [0, 0, .3], [[.45, -2.5], [.85, -2.2], [1.1, -1.4], [1.15, -.4], [1.15, .5], [1.05, 1.4], [.95, 1.9]], { n: 16, sz: 1.05, color: dorsal(16) });
    along(kit, [0, .15, -1.7], [[1.0, 0], [1.15, .4], [1.1, .9], [.85, 1.35], [.4, 1.62], [0, 1.68]], { n: 16, sz: .85, color: dorsal(16) }, .05);
    along(kit, [0, -.45, -1.6], [[.9, 0], [.95, .55], [.75, 1.2], [.3, 1.6], [0, 1.65]], { n: 14, sz: .35, color: TD }, -.12);
    for (let i = 0; i < 9; i++) { const a = -1.2 + i * .3; kit.group({ pos: [Math.sin(a) * .82, -.22, -2.55 - Math.cos(a) * .55], rot: [PI, 0, 0] }, () => kit.lathe([[.06, 0], [0, .22 + (i % 2) * .08]], { n: 5, capStart: true, color: C.BONE })) }
    eyes(kit, .62, .65, -2.85, .16, C.AMBER);
    kit.group({ pos: [0, 1.2, -1.9] }, () => kit.tube([[0, 0, 0], [0, .65, -.2], [0, .95, -.65], [0, .85, -1.05]], [.08, .065, .05, .04], { n: 6, color: TD }));
    spines(kit, [[1.08, -1.0, .8, .9], [1.15, .1, .7, .9], [1.05, 1.1, .6, .8]], TL, .08);
    for (const s of [-1, 1]) kit.group({ pos: [s * 1.0, -.6, -.5], rot: [0, 0, s * .9] }, () => kit.group({ rot: [PI / 2, 0, 0] }, () => kit.prism([[0, -.4], [.6, -.25], [.9, .2], [.4, .5], [0, .4]], .05, TL, T)));
  });
  rig('lurker', { hip: 1.6, hitbox: [3, 3.6, 7.6], gait: 'slither', core: 'CreatureLurker', stride: 2.4, breath: .06,
    segs: [{ shape: 'FishTail', at: [0, .05, 2.2], role: 'tail', k: [2.6, 2.6, 2.6] }],
    glow: glowEyes(.62, .65, -2.85, .16, 'FFE66D').concat([{ kind: 'core', at: [0, 2.05, -2.95], r: .26, color: 'B8FFF4' }]),
    anchors: { crown: [0, 1.25, -1.6], shoulder: [.95, .6, -1.0], chest: [0, -.2, -2.4], ring: 3.4 } });

  // Tempest Wraith (hip 3.6, floating): hooded storm-cloak with a void face.
  creature('CreatureWraith', { smooth: ORG, tint: '4A5A7A', kind: 'creature' }, kit => {
    kit.lathe([[1.55, -2.85], [1.3, -2.2], [1.05, -1.2], [.95, -.2], [1.1, .6], [.95, 1.1], [.6, 1.4]], { n: 18, sz: .78, color: (l, i) => (i + l) % 5 === 0 ? TD : l <= 1 ? TL : T,
      jitter: (l, i) => l === 0 ? 1 + (hash(l, i, 61) - .5) * .45 : 1, lift: (l, i) => l === 0 ? (hash(l, i, 62) - .2) * .9 : 0 });
    ell(kit, 0, 1.75, .05, .95, 1.0, .95, shade(TD, T, T), 2);
    ell(kit, 0, 1.6, -.45, .66, .72, .5, C.VOID, 2);
    kit.lathe([[.62, 1.2], [.72, 1.35], [.66, 1.55]], { n: 14, color: C.BRASS });
    for (let i = 0; i < 5; i++) { const a = i * .5 - 1; kit.jewel(Math.sin(a) * .98, .5 + Math.abs(a) * .2, -Math.cos(a) * .76, .06, .14, .04, C.ICE) }
    eye(kit, -.27, 1.7, -.86, .1, C.ICE); eye(kit, .27, 1.7, -.86, .1, C.ICE);
  });
  rig('wraith', { hip: 3.6, hitbox: [4, 5.6, 3], gait: 'float', core: 'CreatureWraith', breath: .12,
    segs: [{ shape: 'WraithArm', at: [1.0, .9, -.3], rot: [-.3, 0, .35], role: 'armA', k: 2.4 }, { shape: 'WraithArm', at: [-1.0, .9, -.3], rot: [-.3, 0, -.35], role: 'armB', mirror: 'yaw', k: 2.4 }],
    glow: glowEyes(.27, 1.7, -.86, .1, '7FDBFF').concat([0, 1, 2].map(i => ({ kind: 'mote', at: [Math.cos(i * 2.1) * 1.7, 2.6, Math.sin(i * 2.1) * 1.7], r: .14, color: 'CFE8FF', orbit: 1.4 }))),
    anchors: { crown: [0, 2.7, .05], shoulder: [1.0, 1.1, 0], chest: [0, .6, -.9], ring: 2.4 } });

  // Starborn Sentinel (hip 4.2): marble titan, star core, crystal head, halo.
  creature('CreatureSentinel', { smooth: HARD, tint: '5FA8D3', kind: 'creature' }, kit => {
    kit.lathe([[.95, -1.25], [1.1, -.9], [1.45, -.1], [1.62, .8], [1.55, 1.9], [1.1, 2.4], [.5, 2.55]], { n: 16, sz: .7, color: (l, i) => l === 3 ? TL : (i % 4 === 1 ? TD : T) });
    kit.lathe([[1.0, -1.25], [1.25, -1.45], [1.15, -1.7], [.85, -1.85]], { n: 16, sz: .7, color: C.BRASS, capEnd: true });
    kit.group({ pos: [0, 1.0, -1.08], rot: [-PI / 2, 0, 0] }, () => kit.lathe([[.6, 0], [.66, .06], [.5, .12]], { n: 16, color: C.GOLD, capEnd: true, capColor: C.SOCKET }));
    kit.group({ pos: [0, 3.15, 0] }, () => kit.lathe([[0, -.75], [.52, -.15], [.55, .05], [.38, .45], [0, .95]], { n: 8, color: (l, i) => l === 1 && i % 2 ? C.GLINT : l === 0 ? TD : C.ICE }));
    kit.ring(1.45, .1, .08, C.GOLD, 32, 0, 0, PI * 2, 3.3);
    kit.ring(1.3, .05, .06, C.BRASS, 32, 0, 0, PI * 2, 3.3);
    for (let i = 0; i < 8; i++) { const a = i * PI / 4; kit.jewel(Math.cos(a) * 1.45, 3.3 + Math.sin(a) * 1.45, .02, .1, .1, .1, C.GOLD) }
    for (let i = 0; i < 6; i++) kit.group({ pos: [(i - 2.5) * .45, .2 + (i % 2) * .3, -1.05], rot: [0, 0, 0] }, () => kit.box(0, 0, 0, .06, .5, .04, C.RUNE));
  });
  rig('sentinel', { hip: 4.2, hitbox: [5.4, 8.4, 3], gait: 'biped', core: 'CreatureSentinel', stride: 2.4, breath: .05,
    segs: [
      { shape: 'StoneLeg', at: [-.8, -1.5, 0], role: 'legA', k: [1.8, 2.75, 1.8] }, { shape: 'StoneLeg', at: [.8, -1.5, 0], role: 'legB', k: [1.8, 2.75, 1.8] },
      { shape: 'StoneArm', at: [-2.05, 1.8, 0], role: 'armB', mirror: 'yaw', k: [2.2, 3.0, 2.2] }, { shape: 'StoneArm', at: [2.05, 1.8, 0], role: 'armA', k: [2.2, 3.0, 2.2] },
      ...[0, 1, 2, 3].map(i => ({ shape: 'CrystalShard', at: [Math.cos(i * PI / 2 + PI / 4) * 3.0, 1.2, Math.sin(i * PI / 2 + PI / 4) * 3.0], role: 'orbit', k: 1.6, phase: i * PI / 2 }))],
    glow: [{ kind: 'core', at: [0, 1.0, -1.2], r: .45, color: 'FFD166' }, { kind: 'eye', at: [0, 3.2, -.55], r: .18, color: 'FFF4C2' }],
    anchors: { crown: [0, 4.15, 0], shoulder: [2.05, 2.25, 0], chest: [0, 1.0, -1.25], ring: 3.4 } });

  // Serpent (hip 2.2): a horned sea-serpent head and neck (coils follow).
  creature('CreatureSerpent', { smooth: ORG, tint: '3FB8AF', kind: 'creature' }, kit => {
    kit.tube([[0, -.9, -.2], [0, -.1, -1.3], [0, .6, -2.4], [0, .95, -3.15]], [.85, .78, .7, .62], { n: 14, color: (i, k) => k < 3 || k > 10 ? TD : k >= 6 && k <= 8 ? TL : T });
    along(kit, [0, 1.15, -3.2], [[.75, 0], [.85, .4], [.75, .9], [.5, 1.3], [.3, 1.55], [0, 1.62]], { n: 14, sz: .85, color: dorsal(14) }, .05);
    along(kit, [0, .62, -3.3], [[.6, 0], [.6, .55], [.35, 1.1], [0, 1.25]], { n: 12, sz: .35, color: TD }, -.15);
    eyes(kit, .55, 1.45, -4.1, .15, C.GOLD);
    for (const s of [-1, 1]) {
      horn(kit, [[s * .45, 1.75, -3.4], [s * .65, 2.25, -3.0], [s * .7, 2.6, -2.45], [s * .6, 2.75, -2.0]], .14, C.BONE, 7);
      kit.tube([[s * .62, .95, -4.3], [s * 1.0, .75, -4.4], [s * 1.35, .5, -4.2], [s * 1.55, .2, -3.9]], [.05, .04, .03, .022], { n: 5, color: TL });
    }
    for (let i = 0; i < 4; i++) kit.group({ pos: [0, .5 + i * .32, -.6 - i * .8], rot: [0, PI / 2, 0] }, () => kit.prism([[-.38, 0], [-.12, .5], [.2, .55], [.42, 0]], .05, C.GLASS, TL));
  });
  rig('serpent', { hip: 2.2, hitbox: [3, 4.4, 9.4], gait: 'slither', core: 'CreatureSerpent', stride: 3, breath: .05,
    segs: [
      { shape: 'SerpentCoil', at: [0, -.85, -.2], role: 'coil', k: 1.05, phase: 0 }, { shape: 'SerpentCoil', at: [0, -1.15, .9], role: 'coil', k: .95, phase: 1 },
      { shape: 'SerpentCoil', at: [0, -1.35, 1.9], role: 'coil', k: .82, phase: 2 }, { shape: 'SerpentTail', at: [0, -1.5, 2.8], role: 'coil', k: 1.2, phase: 3 }],
    glow: glowEyes(.55, 1.45, -4.1, .15, 'F6FF8F'), anchors: { crown: [0, 2.0, -3.4], shoulder: [.75, .9, -1.4], chest: [0, .2, -2.6], ring: 3.6 } });

  // Crab (hip 1.4): ridged shell with spines, stalked eyes (claws are limbs).
  creature('CreatureCrab', { smooth: HARD, tint: 'D9774B', kind: 'creature' }, kit => {
    kit.lathe([[1.75, -.45], [2.0, -.2], [2.05, .1], [1.7, .5], [1.0, .85], [0, .98]], { n: 20, sz: .78, color: (l, i) => l >= 3 ? (i % 5 === 0 ? TL : T) : l === 2 ? TD : TL,
      jitter: (l, i) => l === 2 ? (i % 2 ? 1.05 : .95) : 1 });
    kit.lathe([[1.7, -.7], [1.75, -.45]], { n: 20, sz: .78, color: TL, capStart: true, capColor: TL });
    for (let i = 0; i < 7; i++) { const a = PI + .4 + i * (PI - .8) / 6; horn(kit, [[Math.cos(a) * 1.95, .05, Math.sin(a) * 1.5], [Math.cos(a) * 2.25, .1, Math.sin(a) * 1.72]], .1, C.BONE, 5) }
    for (let i = 0; i < 5; i++) { const a = i * 1.25; ell(kit, Math.cos(a) * .8, .82, Math.sin(a) * .6, .22, .1, .2, C.CORAL, 1) }
    for (const s of [-1, 1]) {
      kit.tube([[s * .42, .55, -1.3], [s * .45, 1.1, -1.45], [s * .45, 1.35, -1.5]], [.1, .08, .07], { n: 6, color: TD });
      ell(kit, s * .45, 1.5, -1.52, .2, .2, .2, C.SOCKET, 1);
      kit.jewel(s * .45, 1.5, -1.7, .1, .1, .05, C.AMBER);
    }
    for (const x of [-.25, 0, .25]) kit.group({ pos: [x, -.1, -1.58], rot: [PI, 0, 0] }, () => kit.lathe([[.06, 0], [0, .22]], { n: 5, capStart: true, color: C.BONE }));
  });
  rig('crab', { hip: 1.4, hitbox: [6.2, 2.8, 4.4], gait: 'hex', core: 'CreatureCrab', stride: 1.4, breath: .04,
    segs: [-.5, .4, 1.3].flatMap((z, i) => [
      { shape: 'ChitinLeg', at: [1.5, -.35, z], rot: [0, .2 - i * .25, 0], role: i % 2 ? 'legB' : 'legA', k: [1.6, 1.2, 1.6] },
      { shape: 'ChitinLeg', at: [-1.5, -.35, z], rot: [0, -.2 + i * .25, 0], role: i % 2 ? 'legA' : 'legB', mirror: 'yaw', k: [1.6, 1.2, 1.6] }])
      .concat([{ shape: 'CrabClaw', at: [1.45, -.05, -1.2], rot: [0, -.25, 0], role: 'claw', k: 1.6 }, { shape: 'CrabClaw', at: [-1.45, -.05, -1.2], rot: [0, .25, 0], role: 'claw', mirror: 'roll', k: 1.6 }]),
    glow: [{ kind: 'eye', at: [-.45, 1.5, -1.75], r: .1, color: 'FFE680' }, { kind: 'eye', at: [.45, 1.5, -1.75], r: .1, color: 'FFE680' }],
    anchors: { crown: [0, .95, 0], shoulder: [1.4, .5, -.6], chest: [0, .2, -1.5], ring: 3.2 } });

  // Ray (hip 2.8, flying): a manta body with cephalic horns and a whip tail.
  creature('CreatureRay', { smooth: ORG, tint: '8FB8D6', kind: 'creature' }, kit => {
    along(kit, [0, 0, .2], [[0, -2.0], [.55, -1.85], [1.05, -1.2], [1.2, -.3], [1.1, .6], [.8, 1.3], [.45, 1.75], [0, 1.9]], { n: 16, sz: .32, color: dorsal(16, TD, T, C.FUR) });
    kit.tube([[0, 0, 1.9], [0, .05, 2.8], [0, .1, 3.7], [0, .2, 4.6]], [.16, .1, .06, .025], { n: 6, color: TD });
    kit.group({ pos: [0, .22, 4.55], rot: [0, PI / 2, 0] }, () => kit.prism([[-.1, 0], [0, .35], [.4, 0]], .04, TL, TL));
    for (const s of [-1, 1]) kit.tube([[s * .55, 0, -1.6], [s * .7, -.05, -2.1], [s * .62, -.3, -2.45]], [.16, .12, .05], { n: 7, color: TD });
    eyes(kit, .82, .25, -1.45, .12, C.ICE);
    for (const [x, z] of [[-.45, .3], [.45, .55], [0, .95], [-.3, 1.3], [.3, -.3]]) kit.jewel(x, .36, z, .11, .03, .11, C.ICE);
  });
  rig('ray', { hip: 2.8, hitbox: [7.4, 1.8, 5.4], gait: 'glide', core: 'CreatureRay', flap: 2.2, breath: .08,
    segs: [{ shape: 'RayFin', at: [.95, 0, .2], role: 'wing', k: [2.6, 1.0, 2.9] }, { shape: 'RayFin', at: [-.95, 0, .2], role: 'wing', mirror: 'roll', k: [2.6, 1.0, 2.9] }],
    glow: glowEyes(.82, .25, -1.45, .12, 'BFF7E6').concat([{ kind: 'rune', at: [0, .4, .5], r: .2, color: 'BFF7E6' }]),
    anchors: { crown: [0, .45, -.8], chest: [0, -.3, -1.2], ring: 3.4 } });

  // Driftbell Jelly (hip 3.4, floating): frilled bell with a glowing core.
  creature('CreatureJelly', { smooth: ORG, tint: 'B39DDB', kind: 'creature' }, kit => {
    kit.lathe([[1.7, -.05], [1.68, .3], [1.55, .95], [1.25, 1.65], [.75, 2.25], [.3, 2.55], [0, 2.62]], { n: 20, color: (l, i) => l === 0 ? TD : (i + l) % 4 === 0 ? TL : T });
    kit.lathe([[1.75, -.25], [1.82, -.1], [1.7, -.05]], { n: 20, color: TL, jitter: (l, i) => i % 2 ? 1.06 : .96 });
    kit.lathe([[1.2, .1], [.9, .25], [.4, .35], [0, .38]], { n: 16, color: C.VOID, capStart: false });
    for (let i = 0; i < 4; i++) { const a = i * PI / 2 + PI / 4; kit.group({ pos: [Math.cos(a) * .35, -.1, Math.sin(a) * .35] }, () => kit.tube([[0, 0, 0], [Math.cos(a) * .2, -.6, Math.sin(a) * .2], [Math.cos(a) * .05, -1.4, Math.sin(a) * .05]], [.16, .1, .03], { n: 6, color: TL })) }
    for (let i = 0; i < 10; i++) { const a = i * PI / 5; kit.jewel(Math.cos(a) * 1.4, 1.2, Math.sin(a) * 1.4, .07, .3, .07, C.GLINT) }
    eyes(kit, .45, 1.35, -1.38, .13, C.GLINT);
  });
  rig('jelly', { hip: 3.4, hitbox: [3.8, 5.6, 3.8], gait: 'float', core: 'CreatureJelly', breath: .18, pulse: true,
    segs: [0, 1, 2, 3, 4, 5].map(i => ({ shape: 'JellyTendril', at: [Math.cos(i * PI / 3) * 1.25, -.15, Math.sin(i * PI / 3) * 1.25], role: 'tendril', k: [1.6, 2.6 + (i % 2) * .6, 1.6], phase: i })),
    glow: glowEyes(.45, 1.35, -1.38, .13, 'FFFFFF').concat([{ kind: 'core', at: [0, 1.1, 0], r: .6, color: 'E8DBFF' }]),
    anchors: { crown: [0, 2.6, 0], chest: [0, 1.0, -1.5], ring: 2.2 } });

  // Riftmaw Stalker (hip 2.2): a hulking rift hound with crystal spines.
  creature('CreatureRiftmaw', { smooth: ORG, tint: '5B3F8C', kind: 'creature' }, kit => {
    along(kit, [0, .25, .3], [[.4, -2.3], [.95, -2.0], [1.2, -1.2], [1.35, -.2], [1.5, .8], [1.4, 1.6], [1.1, 2.15]], { n: 16, sx: .9, color: dorsal(16) });
    along(kit, [0, .95, -2.6], [[.75, 0], [.85, .4], [.75, .85], [.5, 1.25], [.3, 1.4]], { n: 14, sz: .85, color: dorsal(14) }, .12);
    along(kit, [0, .35, -2.7], [[.65, 0], [.65, .5], [.4, 1.05], [0, 1.15]], { n: 12, sz: .4, color: TD }, -.25);
    for (let i = 0; i < 7; i++) { const a = -1 + i * .33; kit.group({ pos: [Math.sin(a) * .55, .55, -3.55 - Math.cos(a) * .2], rot: [PI, 0, 0] }, () => kit.lathe([[.05, 0], [0, .2 + (i % 2) * .1]], { n: 5, capStart: true, color: C.BONE })) }
    eyes(kit, .45, 1.25, -3.6, .13, C.LAVENDER);
    for (let i = 0; i < 5; i++) {
      const z = -1.8 + i * .85, h = 1.3 - i * .15;
      kit.group({ pos: [0, 1.35 - i * .05, z], rot: [-.35, 0, 0] }, () => kit.lathe([[0, -.1], [.2, .2], [.22, h * .5], [0, h]], { n: 6, color: (l, j) => j % 2 ? C.GLASS : TL }));
      for (const s of [-1, 1]) kit.group({ pos: [s * .55, 1.1 - i * .05, z + .3], rot: [-.4, 0, s * .6] }, () => kit.lathe([[0, -.05], [.1, .12], [0, h * .5]], { n: 5, color: C.GLASS }));
    }
  });
  rig('riftmaw', { hip: 2.2, hitbox: [3.6, 4.2, 7.2], gait: 'quad', core: 'CreatureRiftmaw', stride: 2.6, breath: .07,
    segs: [
      { shape: 'ClawLeg', at: [-.95, -.4, -1.6], role: 'legA', k: [1.7, 1.85, 1.7] }, { shape: 'ClawLeg', at: [.95, -.4, -1.6], role: 'legB', k: [1.7, 1.85, 1.7] },
      { shape: 'ClawLeg', at: [-.9, -.4, 1.6], role: 'legB', k: [1.6, 1.85, 1.6] }, { shape: 'ClawLeg', at: [.9, -.4, 1.6], role: 'legA', k: [1.6, 1.85, 1.6] },
      { shape: 'ScaleTail', at: [0, .6, 2.35], rot: [-.3, 0, 0], role: 'tail', k: 2.4 }],
    glow: glowEyes(.45, 1.25, -3.6, .13, 'C77DFF').concat([{ kind: 'rune', at: [0, 1.55, .1], r: .16, color: 'C77DFF', bar: [.18, 3.2] }]),
    anchors: { crown: [0, 1.75, -2.4], shoulder: [1.1, 1.1, -1.5], chest: [0, .3, -2.4], ring: 3.4 } });

  // Shardglass Seer (hip 3.2, floating): crystal-faced robed oracle, halo.
  creature('CreatureSeer', { smooth: ORG, tint: '7A5BC4', kind: 'creature' }, kit => {
    kit.lathe([[1.35, -2.9], [1.2, -2.2], [1.0, -1.2], [.85, -.1], [.95, .7], [.75, 1.05], [.4, 1.2]], { n: 18, sz: .85, color: (l, i) => (i % 6 === 0) ? C.GOLD : l <= 1 ? TL : T,
      lift: (l, i) => l === 0 ? (hash(l, i, 81) - .5) * .5 : 0 });
    kit.group({ pos: [0, 1.65, 0] }, () => kit.lathe([[0, -.6], [.42, -.15], [.46, .1], [.3, .5], [0, .8]], { n: 8, color: (l, i) => l === 1 && i % 2 ? C.GLINT : C.ICE }));
    kit.lathe([[.85, 1.25], [.8, 1.75], [.62, 2.3], [.3, 2.65], [0, 2.75]], { n: 14, sz: .95, color: (l, i) => { const s = Math.sin((i + .5) * 2 * PI / 14); return s < -.55 ? C.VOID : TD } });
    kit.ring(1.15, .08, .06, C.GOLD, 32, PI / 2 - .25, 0, PI * 2, 3.05);
    for (let i = 0; i < 6; i++) { const a = i * PI / 3; kit.jewel(Math.cos(a) * 1.15, 3.05 + Math.sin(a) * .28, Math.sin(a) * 1.12, .08, .16, .08, C.ICE) }
    for (let i = 0; i < 5; i++) kit.group({ pos: [0, .4 - i * .5, -.92 - i * .05], rot: [0, 0, PI / 4] }, () => kit.box(0, 0, 0, .14, .14, .05, C.GOLD));
  });
  rig('seer', { hip: 3.2, hitbox: [3.4, 6.2, 3.4], gait: 'float', core: 'CreatureSeer', breath: .1,
    segs: [{ shape: 'WraithArm', at: [.95, .75, -.2], rot: [-.25, 0, .3], role: 'armA', k: 2.1 }, { shape: 'WraithArm', at: [-.95, .75, -.2], rot: [-.25, 0, -.3], role: 'armB', mirror: 'yaw', k: 2.1 },
      ...[0, 1, 2, 3, 4].map(i => ({ shape: 'CrystalShard', at: [Math.cos(i * 2 * PI / 5) * 2.3, .7 + (i % 2) * .5, Math.sin(i * 2 * PI / 5) * 2.3], role: 'orbit', k: 1.25, phase: i * 2 * PI / 5 }))],
    glow: [{ kind: 'eye', at: [-.2, 1.7, -.42], r: .1, color: 'FFFFFF' }, { kind: 'eye', at: [.2, 1.7, -.42], r: .1, color: 'FFFFFF' }, { kind: 'core', at: [0, 1.65, 0], r: .3, color: 'BFF4FF' }],
    anchors: { crown: [0, 2.8, 0], shoulder: [.95, 1.0, 0], chest: [0, .5, -.95], ring: 2 } });

  // Crownforged Colossus (hip 4.6): a towering forge-construct, crystal crest.
  creature('CreatureColossus', { smooth: HARD, tint: '8A6E9E', kind: 'creature' }, kit => {
    kit.lathe([[1.1, -1.2], [1.5, -.85], [1.85, .1], [2.05, 1.05], [1.95, 2.1], [1.4, 2.7], [.7, 2.9]], { n: 18, sz: .7, color: (l, i) => l === 3 ? C.BRASS : (i % 3 === 0 ? TD : T) });
    kit.lathe([[1.2, -1.75], [1.35, -1.45], [1.15, -1.2]], { n: 16, sz: .72, color: C.IRON, capStart: true });
    for (let l = 0; l < 2; l++) for (let i = 0; i < 9; i++) { const a = PI + .5 + i * (PI - 1) / 8; kit.jewel(Math.cos(a) * 1.9, .4 + l * 1.3, Math.sin(a) * 1.4, .08, .08, .08, C.BRASS) }
    kit.group({ pos: [0, 1.2, -1.42], rot: [-PI / 2, 0, 0] }, () => kit.lathe([[.75, 0], [.8, .1], [.62, .2], [.5, .24]], { n: 16, color: (l) => l === 1 ? C.GOLD : C.IRON, capEnd: true, capColor: C.SOCKET }));
    kit.group({ pos: [0, 3.15, -.2] }, () => {
      kit.bevelBox(0, .45, 0, 1.8, 1.5, 1.7, .3, { top: TD, side: T, bevel: C.BRASS, bottom: C.IRON });
      kit.bevelBox(0, .5, -.84, 1.4, .3, .12, .05, C.SOCKET);
      for (let i = 0; i < 5; i++) kit.group({ pos: [(i - 2) * .38, 1.15, 0], rot: [0, 0, (i - 2) * -.18] }, () => kit.lathe([[0, -.1], [.16, .1], [.18, .4], [0, 1.25 - Math.abs(i - 2) * .3]], { n: 6, color: (l, j) => j % 2 ? C.GLASS : TL }));
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
    along(kit, [0, 0, .5], [[.3, -2.2], [.85, -1.9], [1.1, -1.1], [1.15, -.1], [1.05, .9], [.7, 1.7], [.45, 2.0]], { n: 16, sx: .95, color: dorsal(16) });
    kit.tube([[0, .4, -1.35], [0, 1.0, -2.0], [0, 1.45, -2.65], [0, 1.6, -3.1]], [.62, .52, .44, .4], { n: 12, color: (i, k) => k < 3 || k > 9 ? TD : k >= 5 && k <= 7 ? TL : T });
    along(kit, [0, 1.6, -3.05], [[.48, 0], [.55, .35], [.45, .8], [.28, 1.15], [.12, 1.4], [0, 1.45]], { n: 12, sz: .8, color: dorsal(12) }, .06);
    along(kit, [0, 1.25, -3.2], [[.4, 0], [.36, .55], [.18, 1.05], [0, 1.15]], { n: 10, sz: .35, color: TD }, -.18);
    for (let i = 0; i < 6; i++) { const a = -1 + i * .4; kit.group({ pos: [Math.sin(a) * .3, 1.38, -4.1 - Math.cos(a) * .12], rot: [PI, 0, 0] }, () => kit.lathe([[.035, 0], [0, .14]], { n: 5, capStart: true, color: C.BONE })) }
    eyes(kit, .36, 1.85, -3.75, .11, C.LAVENDER);
    for (const s of [-1, 1]) {
      horn(kit, [[s * .3, 2.0, -3.2], [s * .5, 2.35, -2.8], [s * .62, 2.6, -2.25], [s * .58, 2.75, -1.8]], .14, C.HORN, 7);
      if (wyrm) horn(kit, [[s * .45, 1.7, -3.0], [s * .9, 1.85, -2.7], [s * 1.25, 1.85, -2.25]], .09, C.HORN, 6);
    }
    spines(kit, [[1.95, -2.2, .45, .45, -.6], [1.75, -1.6, .55, .5, -.5], [1.2, -.6, .6, .6], [1.15, .4, .55, .6], [1.0, 1.4, .45, .55]], wyrm ? C.GLASS : TL, .09);
    kit.group({ pos: [0, -.78, .4] }, () => along(kit, [0, 0, 0], [[.5, -1.6], [.7, -1.0], [.72, 0], [.6, 1.0], [.3, 1.6]], { n: 12, sz: .4, color: (l, i) => (l % 2 ? C.GOLD : TL) }));
    if (wyrm) {
      for (let i = 0; i < 7; i++) { const a = i * .45 - 1.35; kit.group({ pos: [Math.sin(a) * .5, 1.55 + Math.cos(a) * .3, -2.45], rot: [.6, a, 0] }, () => kit.prism([[-.1, 0], [0, .6 - Math.abs(a) * .15], [.1, 0]], .05, C.GLASS, TL)) }
    }
  };
  creature('CreatureDrake', { smooth: ORG, tint: '4B3F72', kind: 'creature' }, kit => drakeBody(kit, false));
  creature('CreatureWyrm', { smooth: ORG, tint: '2E2448', kind: 'creature' }, kit => drakeBody(kit, true));
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

  // Sovereign (hip 4.4): the crowned marble king, mantle, robe and blade.
  creature('CreatureSovereign', { smooth: HARD, tint: 'D9CBA3', kind: 'creature' }, kit => {
    kit.lathe([[1.0, -1.2], [1.25, -.6], [1.55, .4], [1.65, 1.4], [1.45, 2.3], [.9, 2.75]], { n: 18, sz: .7, color: (l, i) => l === 2 ? C.GOLD : (i % 4 === 0 ? TL : T) });
    kit.lathe([[2.0, -4.35], [1.85, -3.3], [1.55, -2.2], [1.25, -1.3], [1.05, -1.0]], { n: 20, sz: .8, color: (l, i) => (i % 5 === 0 ? C.GOLD : l <= 1 ? TD : C.CRIMSON), lift: (l, i) => l === 0 ? (hash(l, i, 91) - .5) * .3 : 0 });
    kit.lathe([[2.25, 2.25], [2.35, 2.6], [2.0, 2.95], [1.2, 3.15], [.7, 3.2]], { n: 20, sz: .72, color: (l) => l === 1 ? C.GOLD : C.CRIMSON });
    kit.group({ pos: [0, 1.4, -1.12], rot: [-PI / 2, 0, 0] }, () => kit.lathe([[.62, 0], [.7, .08], [.55, .16]], { n: 16, color: C.GOLD, capEnd: true, capColor: C.SOCKET }));
    ell(kit, 0, 4.1, -.1, .85, .9, .85, C.GLASS, 2);
    ell(kit, 0, 4.05, -.45, .6, .55, .45, C.VOID, 1);
    for (let i = 0; i < 10; i++) { const a = i * PI / 5; kit.jewel(Math.cos(a) * 1.35, 2.85, Math.sin(a) * .98, .08, .08, .08, C.GOLD) }
    for (let i = 0; i < 5; i++) kit.group({ pos: [0, -1.6 - i * .55, -1.15 - i * .14], rot: [0, 0, PI / 4] }, () => kit.box(0, 0, 0, .18, .18, .06, C.GOLD));
  });
  rig('sovereign', { hip: 4.4, hitbox: [6, 9.4, 4], gait: 'biped', core: 'CreatureSovereign', stride: 2.2, breath: .05,
    segs: [
      { shape: 'StoneLeg', at: [-.8, -2.05, 0], role: 'legA', k: [1.6, 2.35, 1.6] }, { shape: 'StoneLeg', at: [.8, -2.05, 0], role: 'legB', k: [1.6, 2.35, 1.6] },
      { shape: 'StoneArm', at: [-2.4, 2.15, 0], role: 'armB', mirror: 'yaw', k: [2.0, 3.0, 2.0] }, { shape: 'SovereignArm', at: [2.4, 2.15, 0], role: 'armA', k: [2.0, 3.0, 2.0] },
      ...[0, 1, 2, 3].map(i => ({ shape: 'CrystalShard', at: [Math.cos(i * PI / 2 + PI / 4) * 3.6, 2.2, Math.sin(i * PI / 2 + PI / 4) * 3.6], role: 'orbit', k: 1.9, phase: i * PI / 2 }))],
    glow: [{ kind: 'eye', at: [-.3, 4.15, -.85], r: .14, color: 'FFE08A' }, { kind: 'eye', at: [.3, 4.15, -.85], r: .14, color: 'FFE08A' }, { kind: 'core', at: [0, 1.4, -1.25], r: .45, color: 'FFE08A' }],
    anchors: { crown: [0, 4.55, -.1], shoulder: [2.4, 2.55, 0], chest: [0, 1.4, -1.3], ring: 4 } });

  // Hollowcap Shrieker (hip 2.2): a towering mushroom with glowing spots.
  creature('CreatureShrieker', { smooth: ORG, tint: 'C88B5A', kind: 'creature' }, kit => {
    kit.lathe([[.85, -1.9], [.75, -1.2], [.65, -.2], [.68, .6], [.8, 1.1]], { n: 14, color: (l, i) => (i + l) % 4 === 0 ? C.FUR : C.CLOTH, jitter: (l, i) => 1 + (hash(l, i, 33) - .5) * .1 });
    kit.lathe([[2.2, .95], [2.35, 1.2], [2.15, 1.75], [1.6, 2.35], [.9, 2.75], [0, 2.9]], { n: 20, color: (l, i) => l === 0 ? TD : T, jitter: (l, i) => l <= 1 ? 1 + (hash(l, i, 34) - .5) * .12 : 1 });
    kit.lathe([[.75, 1.05], [1.6, .92], [2.2, .95]], { n: 20, color: (l, i) => i % 2 ? C.CLOTH : C.FUR });
    kit.lathe([[.9, .45], [1.05, .55], [.9, .65]], { n: 14, color: C.FUR, jitter: (l, i) => i % 2 ? 1.1 : .92 });
    ell(kit, 0, -.35, -.66, .42, .3, .12, C.SOCKET, 1);
    for (const x of [-.25, 0, .25]) kit.group({ pos: [x, -.18, -.74], rot: [PI, 0, 0] }, () => kit.lathe([[.04, 0], [0, .12]], { n: 5, capStart: true, color: C.BONE }));
    eyes(kit, .32, .25, -.72, .12, C.AMBER);
  });
  rig('shrieker', { hip: 2.2, hitbox: [4.4, 5, 4.4], gait: 'roots', core: 'CreatureShrieker', stride: 1.2, breath: .09, pulse: true,
    segs: [0, 1, 2].map(i => ({ shape: 'RootLeg', at: [Math.cos(i * 2 * PI / 3 + PI / 2) * .65, -1.75, Math.sin(i * 2 * PI / 3 + PI / 2) * .65], rot: [0, -(i * 2 * PI / 3 + PI / 2), 0], role: i % 2 ? 'legA' : 'legB', k: [1.0, .5, 1.0] })),
    glow: glowEyes(.32, .25, -.72, .12, 'E9F5B0').concat([0, 1, 2, 3, 4].map(i => ({ kind: 'mote', at: [Math.cos(i * 2 * PI / 5) * 1.55, 2.2, Math.sin(i * 2 * PI / 5) * 1.55], r: .24, color: 'E9F5B0' }))),
    anchors: { crown: [0, 2.9, 0], chest: [0, 0, -.8], ring: 2.6 } });

  // Mirrorscale Basilisk (hip 1.4): a long lizard plated with mirror scales.
  creature('CreatureBasilisk', { smooth: ORG, tint: '6F8F7A', kind: 'creature' }, kit => {
    along(kit, [0, 0, .2], [[.3, -2.4], [.75, -2.1], [.92, -1.2], [.95, 0], [.88, 1.2], [.6, 2.0], [.45, 2.3]], { n: 14, color: dorsal(14) });
    along(kit, [0, .3, -2.45], [[.6, 0], [.68, .4], [.55, .95], [.3, 1.4], [0, 1.55]], { n: 12, sz: .78, color: dorsal(12) }, .05);
    eyes(kit, .42, .58, -3.55, .12, C.GOLD);
    for (let i = 0; i < 8; i++) { const z = -1.8 + i * .5; kit.group({ pos: [0, .9 - Math.abs(z) * .04, z], rot: [-.25, 0, 0] }, () => kit.lathe([[.32, -.02], [.34, .02]], { n: 10, sz: .4, color: C.GLASS, capStart: true, capEnd: true, capColor: C.GLINT })) }
    for (let i = 0; i < 5; i++) kit.group({ pos: [0, 1.0 - i * .08, -3.0 + i * .28], rot: [-.5, PI / 2, 0] }, () => kit.prism([[-.2, 0], [0, .5 - i * .06], [.2, 0]], .05, C.GLASS, TL));
  });
  rig('basilisk', { hip: 1.4, hitbox: [3, 2.8, 8.4], gait: 'quad', core: 'CreatureBasilisk', stride: 1.8, breath: .04, sprawl: true,
    segs: [
      { shape: 'ClawLeg', at: [-.8, -.35, -1.4], rot: [0, 0, -.35], role: 'legA', k: 1.15 }, { shape: 'ClawLeg', at: [.8, -.35, -1.4], rot: [0, 0, .35], role: 'legB', k: 1.15 },
      { shape: 'ClawLeg', at: [-.8, -.35, 1.3], rot: [0, 0, -.35], role: 'legB', k: 1.15 }, { shape: 'ClawLeg', at: [.8, -.35, 1.3], rot: [0, 0, .35], role: 'legA', k: 1.15 },
      { shape: 'ScaleTail', at: [0, .05, 2.45], role: 'tail', k: [2.0, 2.0, 1.9] }],
    glow: glowEyes(.42, .58, -3.55, .12, 'E9FBFF'), anchors: { crown: [0, .95, -2.6], shoulder: [.8, .7, -1.5], chest: [0, 0, -2.4], ring: 3.6 } });

  // Thundercrag Gargant (hip 4): a crag giant crowned by a thunderhead.
  creature('CreatureGargant', { smooth: HARD, tint: '6F7B8C', kind: 'creature' }, kit => {
    ell(kit, 0, 1.0, 0, 2.35, 2.05, 1.55, shade(TL, T, TD), 2, { seed: 51, amount: .07 });
    ell(kit, 0, -1.25, 0, 1.55, .8, 1.15, shade(T, TD, TD), 2, { seed: 52, amount: .06 });
    ell(kit, 0, 3.55, -.35, 1.0, .85, .95, shade(TL, T, TD), 2, { seed: 53, amount: .08 });
    kit.bevelBox(0, 3.55, -1.2, 1.1, .22, .12, .04, C.SOCKET);
    for (let i = 0; i < 6; i++) { const a = i * 1.05; ell(kit, Math.cos(a) * .9, 5.1 + (i % 2) * .25, Math.sin(a) * .7 + .3, .75, .55, .7, i % 2 ? C.STONE_LIGHT : C.SLATE, 1, { seed: 60 + i, amount: .1 }) }
    ell(kit, 0, 5.25, .3, 1.05, .7, .95, C.STONE_LIGHT, 2, { seed: 70, amount: .08 });
    for (let i = 0; i < 4; i++) kit.group({ pos: [(i - 1.5) * .7, 1.2 + (i % 2) * .6, -1.48], rot: [0, 0, (i % 2 ? .4 : -.4)] }, () => kit.box(0, 0, 0, .1, .9, .05, C.RUNE));
    for (const s of [-1, 1]) for (let i = 0; i < 3; i++) horn(kit, [[s * (1.6 + i * .2), 2.4 - i * .4, .5], [s * (2.0 + i * .25), 2.7 - i * .4, .8]], .2, C.STONE_DARK, 6);
  });
  rig('gargant', { hip: 4, hitbox: [6.4, 9, 4], gait: 'biped', core: 'CreatureGargant', stride: 2.8, breath: .06,
    segs: [
      { shape: 'StoneLeg', at: [-1.05, -1.75, 0], role: 'legA', k: [2.2, 2.3, 2.2] }, { shape: 'StoneLeg', at: [1.05, -1.75, 0], role: 'legB', k: [2.2, 2.3, 2.2] },
      { shape: 'StoneArm', at: [-2.65, 2.2, .1], role: 'armB', mirror: 'yaw', k: [2.8, 4.1, 2.8] }, { shape: 'StoneArm', at: [2.65, 2.2, .1], role: 'armA', k: [2.8, 4.1, 2.8] }],
    glow: [{ kind: 'eye', at: [0, 3.55, -1.3], r: .18, color: 'BFE4FF', bar: [1.0, .14] }, { kind: 'core', at: [0, 5.2, .3], r: .55, color: 'BFE4FF', flicker: true }],
    anchors: { crown: [0, 4.35, -.35], shoulder: [2.6, 2.7, 0], chest: [0, 1.2, -1.55], ring: 3.8 } });

  // Umbral Dreadmaw (hip 2.2): a shadow beast with tattered shade fins.
  creature('CreatureDreadmaw', { smooth: ORG, tint: '2B2238', kind: 'creature' }, kit => {
    along(kit, [0, .2, .4], [[.35, -2.4], [.9, -2.1], [1.2, -1.2], [1.3, -.1], [1.4, .9], [1.25, 1.75], [.9, 2.35]], { n: 16, sx: .88, color: dorsal(16, C.VOID, T, TD) });
    along(kit, [0, .95, -2.7], [[.78, 0], [.88, .45], [.75, .95], [.45, 1.35], [.2, 1.45]], { n: 14, sz: .82, color: dorsal(14, C.VOID, T, TD) }, .1);
    along(kit, [0, .3, -2.85], [[.7, 0], [.7, .55], [.42, 1.05], [0, 1.15]], { n: 12, sz: .42, color: TD }, -.3);
    for (let i = 0; i < 8; i++) { const a = -1.05 + i * .3; kit.group({ pos: [Math.sin(a) * .6, .55, -3.7 - Math.cos(a) * .2], rot: [PI, 0, 0] }, () => kit.lathe([[.05, 0], [0, .24 + (i % 2) * .12]], { n: 5, capStart: true, color: C.BONE })) }
    eyes(kit, .48, 1.3, -3.75, .13, C.LAVENDER);
    for (let i = 0; i < 6; i++) {
      const z = -2.0 + i * .75;
      kit.group({ pos: [0, 1.45 - i * .08, z], rot: [-.6, PI / 2, 0] }, () => kit.prism([[-.35, 0], [-.25, .6 - i * .05], [0, 1.15 - i * .1], [.1, .7], [.4, 0]], .05, C.VOID, TL));
    }
    for (const s of [-1, 1]) horn(kit, [[s * .45, 1.6, -2.5], [s * .85, 1.95, -2.2], [s * 1.0, 2.1, -1.7]], .13, C.BONE, 6);
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
    ell(kit, 0, -.45, 0, 1.5, 1.35, 1.5, shade(T, T, TD), 2, { squash: .75 });
    ell(kit, .55, .3, -.75, .32, .2, .2, C.GLINT, 1);
    eyes(kit, .45, -.1, -1.25, .17, C.GLINT);
    kit.group({ pos: [0, -.6, -1.38] }, () => kit.lathe([[.22, -.02], [.25, 0], [.22, .02]], { n: 10, sz: .4, color: C.SOCKET, capStart: true, capEnd: true }));
  });
  rig('blob', { hip: 1.5, hitbox: [3, 3, 3], gait: 'hop', core: 'CreatureBlob', stride: 1.2, breath: .1,
    segs: [], glow: glowEyes(.45, -.1, -1.25, .17, 'FFE680'), anchors: { crown: [0, .9, 0], chest: [0, -.4, -1.4], ring: 1.8 } });

  // -------------------------------------------------------------------------
  // Pet companions (pets.client.lua): each pet form, about 1 stud long.
  // -------------------------------------------------------------------------
  creature('PetFlyer', { smooth: ORG, tint: 'F2C14E', kind: 'pet' }, kit => {
    ell(kit, 0, 0, 0, .5, .46, .62, shade(TD, T, C.FUR), 2);
    ell(kit, 0, .5, -.45, .38, .36, .38, shade(TD, T, C.FUR), 2);
    kit.group({ pos: [0, .44, -.82], rot: [-PI / 2 + .3, 0, 0] }, () => kit.lathe([[.1, 0], [.06, .12], [0, .2]], { n: 8, color: C.GOLD, capStart: true }));
    eyes(kit, .17, .58, -.74, .07, C.GLINT);
    for (let i = -1; i <= 1; i++) kit.group({ pos: [i * .1, .05, .55], rot: [PI / 2 - .3, i * .3, 0] }, () => kit.prism([[-.07, 0], [0, .45], [.07, 0]], .03, TL, T));
    kit.group({ pos: [0, .85, -.4], rot: [-.3, PI / 2, 0] }, () => kit.prism([[-.1, 0], [0, .25], [.12, 0]], .03, TL, TL));
  });
  creature('PetQuad', { smooth: ORG, tint: 'C98D4F', kind: 'pet' }, kit => {
    along(kit, [0, 0, 0], [[0, -.8], [.32, -.72], [.42, -.3], [.42, .3], [.36, .62], [.2, .78]], { n: 14, sz: .95, color: dorsal(14, TD, T, C.FUR) });
    ell(kit, 0, .42, -.82, .36, .32, .34, shade(TD, T, C.FUR), 2);
    along(kit, [0, .32, -1.05], [[.18, 0], [.14, .2], [0, .28]], { n: 10, color: C.FUR }, -.1);
    ell(kit, 0, .36, -1.33, .05, .04, .03, C.SOCKET, 1);
    eyes(kit, .15, .5, -1.08, .06, C.GLINT);
    for (const s of [-1, 1]) kit.group({ pos: [s * .2, .7, -.8], rot: [0, 0, s * -.25] }, () => kit.lathe([[.1, 0], [.06, .18], [0, .3]], { n: 6, sz: .5, color: (l) => l === 0 ? TD : T, capStart: true }));
  });
  creature('PetShell', { smooth: ORG, tint: '6BAF5A', kind: 'pet' }, kit => {
    kit.lathe([[.72, -.12], [.78, .05], [.68, .3], [.42, .5], [0, .58]], { n: 18, sz: .95, color: (l, i) => l === 0 ? C.GOLD : (i + l) % 3 === 0 ? TD : T });
    kit.lathe([[.7, -.25], [.72, -.12]], { n: 18, sz: .95, color: C.FUR, capStart: true, capColor: C.FUR });
    for (let i = 0; i < 6; i++) { const a = i * PI / 3; kit.jewel(Math.cos(a) * .4, .44, Math.sin(a) * .38, .12, .05, .12, TL) }
    ell(kit, 0, .02, -.88, .26, .24, .3, shade(T, T, C.FUR), 2);
    eyes(kit, .13, .1, -1.1, .055, C.GLINT);
  });
  creature('PetHopper', { smooth: ORG, tint: '8EF0F8', kind: 'pet' }, kit => {
    ell(kit, 0, 0, 0, .56, .5, .56, shade(T, T, C.FUR), 2, { squash: .85 });
    ell(kit, 0, -.12, -.28, .38, .32, .28, C.FUR, 1);
    for (const s of [-1, 1]) { ell(kit, s * .35, -.42, -.05, .2, .1, .3, TD, 1); ell(kit, s * .42, .08, -.24, .1, .1, .08, C.CORAL, 1) }
    eyes(kit, .24, .38, -.4, .1, C.GLINT);
    for (const s of [-1, 1]) kit.group({ pos: [s * .2, .45, .05], rot: [-.35, 0, s * -.2] }, () => kit.lathe([[.09, 0], [.1, .25], [.05, .45], [0, .5]], { n: 8, sz: .5, color: (l) => l > 1 ? TL : T, capStart: true }));
  });
  creature('PetFloat', { smooth: ORG, tint: '9583B9', kind: 'pet' }, kit => {
    kit.lathe([[0, -.55], [.36, -.42], [.52, -.05], [.45, .3], [.25, .52], [.08, .75], [0, .82]], { n: 14, color: (l) => l >= 4 ? TL : l <= 1 ? TD : T, wobble: (l) => [0, l >= 4 ? (l - 3) * .06 : 0] });
    kit.ring(.7, .04, .04, C.GOLD, 24, PI / 2 + .3, 0, PI * 2, 0);
    for (let i = 0; i < 3; i++) kit.group({ pos: [0, -.55 - i * .2, .15 + i * .2] }, () => ell(kit, 0, 0, 0, .14 - i * .03, .14 - i * .03, .14 - i * .03, T, 1));
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
