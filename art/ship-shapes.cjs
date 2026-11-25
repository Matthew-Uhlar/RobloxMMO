// Skysailing (docs/DEPTH-CONTRACT.md §51): the three airship hulls (Skyskiff,
// Windsloop, Aether Galleon), mast, helm wheel and deck cannon, the skydock
// pier, harbour board and mooring bollard, the home Shipwright's Slip, and the
// chart props between the regions (sky reef, wreck, landmark buoy). Loaded by
// art/generate-props.cjs after the rune kit; authored from primitives with the
// deterministic hash. Units are studs at scale 1, +Y up, bows / fronts face -Z.
// Hull fit boxes are the hull body (beam x deck height x length), the host part
// sailing.server.lua builds; rails, castles, bowsprits and fins reach past it.
// Every curved surface is a smooth-shaded loft or lathe; sails are local cloth
// (sailing.client.lua), never part of these meshes.
'use strict';
module.exports = ({ world, C, PI, hash }) => {
  const { TINT, TINT_DARK, TINT_LIGHT } = C;

  // -------------------------------------------------------------------------
  // Hull: a lofted planked body (bow -Z), a deck, gunwale rails on posts, a
  // brass rubbing strake, a keel fin with an aether crystal, side sky-fins and a
  // rudder. Class adds a stern cabin (2) or fore and stern castles with gilded
  // stern windows and gunports (3). TINT faces are the painted hull band.
  // -------------------------------------------------------------------------
  const hull = (kit, L, B, D, cls) => {
    const N = 12 + cls * 2;
    const at = t => {
      const z = -L / 2 + L * t;
      const w = Math.max(.25, B / 2 * (t < .5 ? Math.pow(Math.sin(t / .5 * PI / 2), .55) : 1 - .28 * Math.pow((t - .5) / .5, 2)));
      const top = D + D * .35 * Math.pow(1 - t, 4) + D * .22 * Math.pow(t, 5);
      const keel = D * .55 * Math.pow(1 - t, 3) + D * .3 * Math.pow(t, 4);
      return { z, w, top, keel };
    };
    const sections = [];
    for (let s = 0; s <= N; s++) {
      const { z, w, top, keel } = at(s / N), d = top - keel;
      sections.push({ z, points: [[-w, top], [-w * .99, keel + d * .66], [-w * .86, keel + d * .3], [-w * .4, keel + d * .04], [0, keel - .02],
        [w * .4, keel + d * .04], [w * .86, keel + d * .3], [w * .99, keel + d * .66], [w, top]] });
    }
    kit.loft(sections, { capColor: C.PLANK, color: (s, e) => e === 8 ? C.PLANK : e === 0 || e === 7 ? (s % 2 ? TINT : TINT_DARK)
      : e === 1 || e === 6 ? (s % 3 === 1 ? C.BARK_DARK : C.BARK) : C.BARK_DARK });
    // Deck planking (a bevelled board, slightly inset) and hatch.
    kit.bevelBox(0, D + .08, L * .02, B * .82, .16, L * .8, .05, { top: C.PLANK, side: C.BARK, bevel: C.STRAW, bottom: C.BARK });
    kit.bevelBox(0, D + .22, -L * .1, B * .26, .14, L * .1, .04, { top: C.BARK_DARK, side: C.BARK, bevel: C.BRASS, bottom: C.BARK });
    // Rails and the brass strake.
    for (const side of [-1, 1]) {
      const rail = [], strake = [];
      for (let s = 1; s < N; s++) {
        const { z, w, top, keel } = at(s / N);
        rail.push([side * (w - .12), top + .62, z]);
        strake.push([side * w * 1.005, keel + (top - keel) * .66, z]);
      }
      kit.tube(rail, .09, { n: 4, color: C.PLANK });
      kit.tube(strake, .08, { n: 4, color: C.BRASS });
      rail.forEach(([x, y, z], i) => { if (i % 2 === 0) kit.box(x, y - .32, z, .12, .64, .12, C.BARK) });
      // Sky-fins: ribbed side wings amidships.
      kit.group({ pos: [side * (B / 2 - .1), D * .45, L * .04], rot: [PI / 2, 0, side * -.18] }, () => {
        kit.prism([[0, -L * .14], [side * B * .42, -L * .06], [side * B * .42, L * .02], [0, L * .1]], .1, TINT_LIGHT, C.BRASS);
        kit.tube([[0, 0, 0], [side * B * .42, -L * .02, 0]], .06, { n: 4, color: C.BRASS });
      });
      // Lanterns at the stern quarters.
      kit.jewel(side * B * .36, at(.96).top + 1.0, L * .44, .14, .22, .14, C.FLAME);
    }
    // Keel fin with a glowing aether crystal, and the rudder.
    kit.group({ rot: [0, PI / 2, 0] }, () => kit.prism([[-L * .3, .02], [L * .32, .02], [L * .22, -D * .45], [-L * .18, -D * .3]], .16, C.BARK_DARK, C.BRASS));
    kit.jewel(0, -D * .42, L * .02, .26, .5, .26, TINT_LIGHT);
    kit.bevelBox(0, D * .5, L / 2 + .12, .18, D * .9, L * .06, .04, C.BARK);
    // Bowsprit and figurehead.
    kit.tube([[0, at(0).top - .1, -L / 2 + .3], [0, at(0).top + D * .5, -L / 2 - L * .14]], [.16, .07], { n: 6, color: C.PLANK });
    kit.jewel(0, at(0).top - .1, -L / 2 + .1, .2, .3, .26, C.BRASS);
    if (cls === 1) {
      // A little tiller box and a stern seat.
      kit.bevelBox(0, D + .45, L * .38, B * .5, .5, L * .1, .06, { top: C.PLANK, side: C.BARK, bevel: C.BRASS, bottom: C.BARK });
    }
    if (cls >= 2) {
      // Stern cabin with lit windows.
      const cz = L * .36, cw = B * .66, cd = L * .2;
      kit.bevelBox(0, D + 1.0, cz, cw, 1.9, cd, .1, { top: C.BARK, side: C.PLANK, bevel: C.BARK, bottom: C.BARK });
      kit.bevelBox(0, D + 2.05, cz, cw + .5, .24, cd + .5, .06, TINT_DARK);
      for (const side of [-1, 1]) for (let k = 0; k < 2; k++) kit.box(side * (cw / 2 + .01), D + 1.15, cz - cd * .22 + k * cd * .44, .05, .6, .5, C.FLAME);
      kit.box(0, D + .9, cz - cd / 2 - .01, .9, 1.4, .05, C.BARK_DARK);
    }
    if (cls >= 3) {
      // Forecastle, gilded stern gallery and gunports.
      kit.bevelBox(0, D + .6, -L * .32, B * .7, 1.0, L * .14, .08, { top: C.PLANK, side: C.BARK, bevel: C.BRASS, bottom: C.BARK });
      kit.bevelBox(0, at(1).top + .3, L / 2 - .2, B * .62, 1.4, .3, .06, { top: C.BRASS, side: C.BRASS, bevel: C.GOLD, bottom: C.BRASS });
      for (let k = 0; k < 3; k++) kit.box((k - 1) * B * .18, at(1).top + .3, L / 2 - .02, B * .1, .7, .05, C.FLAME);
      for (const side of [-1, 1]) for (let k = 0; k < 4; k++) {
        const { z, w, top, keel } = at(.28 + k * .14);
        kit.box(side * w * .995, keel + (top - keel) * .5, z, .05, .44, .54, C.INK);
      }
    }
  };
  world('SkiffHull', { smooth: 32, tint: '4AA8E8', kind: 'ship', exactTint: true, fit: [[-3.5, 0, -9], [3.5, 2.6, 9]] }, kit => hull(kit, 18, 7, 2.6, 1));
  world('SloopHull', { smooth: 32, tint: '2E6FA8', kind: 'ship', exactTint: true, fit: [[-4.5, 0, -13], [4.5, 3.2, 13]] }, kit => hull(kit, 26, 9, 3.2, 2));
  world('GalleonHull', { smooth: 32, tint: 'A8423C', kind: 'ship', exactTint: true, fit: [[-6, 0, -18], [6, 4, 18]] }, kit => hull(kit, 36, 12, 4, 3));

  // -------------------------------------------------------------------------
  // Mast: a tapered spar with iron bands, a crow's nest, two yards across X,
  // shroud stays and a pennant. Host is a .7 x 17 x .7 post (fit = the spar).
  // -------------------------------------------------------------------------
  world('ShipMast', { smooth: 30, tint: '4AA8E8', kind: 'prop', fit: [[-.35, 0, -.35], [.35, 17, .35]] }, kit => {
    kit.lathe([[.36, 0], [.34, 6], [.28, 12], [.2, 17], [0, 17.3]], { n: 10, color: C.BARK });
    for (const y of [2, 6.5, 11]) kit.lathe([[.4, y], [.42, y + .12], [.4, y + .24]], { n: 10, color: C.IRON });
    kit.lathe([[.4, 12.4], [1.0, 12.6], [1.05, 13.2], [.95, 13.2], [.9, 12.75], [.38, 12.75]], { n: 12, color: l => l >= 2 ? C.BRASS : C.PLANK });
    for (const [y, w] of [[14.6, 5.4], [5.2, 6.4]]) {
      kit.tube([[-w, y, -.2], [0, y, -.2], [w, y, -.2]], [.1, .16, .1], { n: 6, color: C.PLANK });
      for (const s of [-1, 1]) kit.jewel(s * w, y, -.2, .14, .14, .14, C.BRASS);
    }
    for (const s of [-1, 1]) {
      kit.tube([[s * .3, 15.5, 0], [s * 3.2, 1.0, .9]], .035, { n: 3, color: C.STRAW });
      kit.tube([[s * .3, 15.5, 0], [s * 3.2, 1.0, -.9]], .035, { n: 3, color: C.STRAW });
    }
    kit.prism([[0, 0], [1.8, -.35], [0, -.7]].map(([x, y]) => [x + .2, y + 17]), .04, TINT, TINT_DARK);
  });

  // -------------------------------------------------------------------------
  // Helm wheel on a turned pedestal: eight spokes with handles, brass hub.
  // -------------------------------------------------------------------------
  world('ShipHelm', { smooth: 30, tint: 'C9A24E', kind: 'prop', fit: [[-.8, 0, -.3], [.8, 2.2, .3]] }, kit => {
    kit.lathe([[.32, 0], [.36, .12], [.2, .3], [.16, .9], [.22, 1.1], [.14, 1.3]], { n: 10, capStart: true, capEnd: true, color: l => l === 1 || l === 4 ? C.BRASS : C.BARK });
    kit.group({ pos: [0, 1.45, -.12], rot: [PI / 2, 0, 0] }, () => {
      kit.ring(.62, .1, .1, C.PLANK, 24);
      kit.ring(.3, .06, .08, C.BRASS, 16);
      kit.lathe([[.12, -.12], [.14, 0], [.12, .12]], { n: 10, capStart: true, capEnd: true, color: C.BRASS });
    });
    for (let i = 0; i < 8; i++) {
      const a = i * PI / 4;
      const c = Math.cos(a), s = Math.sin(a);
      kit.tube([[c * .1, 1.45 + s * .1, -.12], [c * .86, 1.45 + s * .86, -.12]], [.04, .035], { n: 5, color: C.BARK });
      kit.jewel(c * .92, 1.45 + s * .92, -.12, .06, .06, .06, C.BRASS);
    }
  });

  // -------------------------------------------------------------------------
  // Deck cannon on a carriage: a banded bronze barrel (muzzle -Z), trunnions,
  // a timber carriage with four trucks, and a TINT-painted cap ring.
  // -------------------------------------------------------------------------
  world('DeckCannon', { smooth: 30, tint: 'C9A24E', kind: 'prop', fit: [[-.6, 0, -1.3], [.6, 1.1, 1.3]] }, kit => {
    kit.bevelBox(0, .3, .2, .9, .34, 1.9, .06, { top: C.BARK, side: C.PLANK, bevel: C.BARK, bottom: C.BARK_DARK });
    for (const sx of [-1, 1]) for (const sz of [-.55, .85]) kit.group({ pos: [sx * .46, .18, sz], rot: [0, 0, PI / 2] }, () => kit.lathe([[.18, -.06], [.2, 0], [.18, .06]], { n: 10, capStart: true, capEnd: true, color: C.IRON }));
    kit.group({ pos: [0, .78, -.1], rot: [-PI / 2 + .08, 0, 0] }, () => {
      kit.lathe([[.3, -1.0], [.34, -.85], [.3, -.6], [.27, 0], [.22, .9], [.27, 1.0], [.27, 1.15], [.16, 1.2], [0, 1.18]],
        { n: 14, capStart: true, color: l => l === 1 || l === 5 ? TINT : l === 6 ? C.INK : C.BRASS, capColor: C.BRASS });
      kit.jewel(0, -1.12, 0, .14, .14, .14, C.BRASS);
    });
    for (const sx of [-1, 1]) kit.group({ pos: [sx * .34, .78, 0], rot: [0, 0, PI / 2] }, () => kit.lathe([[.08, -.06], [.08, .06]], { n: 8, capStart: true, capEnd: true, color: C.IRON }));
  });

  // -------------------------------------------------------------------------
  // Skydock pier (along Z): bevelled deck boards, a brass nosing, iron-capped
  // piles, rope rails between lantern posts, and a cantilevered cargo crane at
  // the sky end. Authored at length 17; the fit box is the whole pier (piles
  // to crane top), filled through the host's declared ShapeBox (world.server.lua).
  // -------------------------------------------------------------------------
  world('SkyDock', { smooth: 30, tint: 'C9A24E', kind: 'pier', fit: [[-3.1, -1.6, -8.5], [3.1, 5.1, 8.5]] }, kit => {
    for (let i = 0; i < 8; i++) {
      const z = -8.5 + i * 2.125;
      kit.bevelBox(0, .12, z + 1.0625, 6, .22, 2.03, .05, { top: hash(i, 1, 51) < .3 ? C.BARK : C.PLANK, side: C.BARK, bevel: C.STRAW, bottom: C.BARK_DARK });
    }
    kit.bevelBox(0, -.16, 0, 5.2, .36, 17, .06, C.BARK_DARK);
    kit.bevelBox(0, .16, 8.4, 6.2, .14, .3, .04, C.BRASS);
    for (const s of [-1, 1]) {
      const posts = [];
      for (let k = 0; k < 4; k++) {
        const z = -7 + k * 4.8;
        posts.push([s * 2.85, 1.25, z]);
        kit.group({ pos: [s * 2.85, 0, z] }, () => {
          kit.lathe([[.2, -1.6], [.2, 1.1], [.26, 1.18], [.2, 1.26], [0, 1.32]], { n: 8, capStart: true, color: l => l >= 2 ? C.IRON : C.BARK });
          if (k % 2 === 1) {
            kit.lathe([[.14, 1.3], [.18, 1.42], [.18, 1.9], [.08, 2.05], [0, 2.1]], { n: 8, color: l => l === 1 ? C.FLAME : C.IRON });
          }
        });
      }
      for (let k = 0; k < posts.length - 1; k++) {
        const [x0, y0, z0] = posts[k], [, , z1] = posts[k + 1];
        kit.tube([[x0, y0, z0], [x0, y0 - .25, (z0 + z1) / 2], [x0, y0, z1]], .05, { n: 4, color: C.STRAW });
      }
    }
    // Cargo crane at the sky end (port side): post, jib, block and hook.
    kit.group({ pos: [-2.4, .2, 7.2] }, () => {
      kit.lathe([[.28, 0], [.24, 4.6], [.18, 4.9]], { n: 8, capEnd: true, color: C.BARK });
      kit.tube([[0, 4.4, 0], [2.6, 4.1, .8]], .12, { n: 6, color: C.PLANK });
      kit.tube([[0, 3.2, 0], [1.6, 4.2, .5]], .07, { n: 4, color: C.IRON });
      kit.box(2.6, 3.9, .8, .22, .3, .22, C.IRON);
      kit.tube([[2.6, 3.75, .8], [2.6, 2.4, .8]], .03, { n: 3, color: C.STRAW });
      kit.ring(.16, .05, .05, C.IRON, 8, PI / 2, 0, PI * 1.5, 2.25);
    });
  });

  // -------------------------------------------------------------------------
  // Harbour board: two posts, a brass-framed board with a chart and three
  // contract slips, and a little gable roof. Host 3.2 x 4.4 x .8 (front -Z).
  // -------------------------------------------------------------------------
  world('HarbourBoard', { smooth: 30, tint: 'C9A24E', kind: 'sign', fit: [[-1.6, 0, -.4], [1.6, 4.4, .4]] }, kit => {
    for (const s of [-1, 1]) kit.bevelBox(s * 1.4, 1.9, 0, .22, 3.8, .22, .04, C.BARK);
    kit.bevelBox(0, 2.6, 0, 2.9, 1.9, .12, .04, { top: C.BARK, side: C.BARK, bevel: C.BRASS, bottom: C.BARK, front: C.PLANK });
    kit.bevelBox(0, 2.6, -.02, 3.1, 2.1, .08, .03, C.BRASS);
    kit.box(-.55, 2.75, -.09, 1.3, 1.1, .03, C.CLOTH);
    for (const [x, y, z] of [[-.9, 3.0, -.11], [-.3, 2.5, -.11], [-.75, 2.35, -.11]]) kit.box(x, y, z, .28, .05, .02, C.INK);
    kit.group({ pos: [-.55, 2.75, -.12], rot: [PI / 2, 0, 0] }, () => kit.ring(.26, .03, .02, TINT, 16));
    for (let k = 0; k < 3; k++) {
      const y = 3.15 - k * .5;
      kit.box(.75, y, -.09, .9, .38, .03, k === 1 ? C.STRAW : C.CLOTH);
      kit.jewel(.75, y + .16, -.12, .05, .05, .04, C.CRIMSON);
    }
    kit.group({ pos: [0, 3.75, 0] }, () => {
      kit.prism([[-1.75, 0], [0, .55], [1.75, 0], [1.75, -.12], [0, .42], [-1.75, -.12]], .9, C.BARK_DARK, C.BARK);
    });
    kit.jewel(0, 4.32, 0, .12, .14, .12, C.BRASS);
  });

  // -------------------------------------------------------------------------
  // Mooring bollard: an iron double bitt on a plinth with a coiled hawser and a
  // lantern hook. Host 1.6 x 2.4 x 1.6.
  // -------------------------------------------------------------------------
  world('MooringBollard', { smooth: 30, tint: 'C9A24E', kind: 'prop', fit: [[-.8, 0, -.8], [.8, 2.4, .8]] }, kit => {
    kit.bevelBox(0, .12, 0, 1.6, .24, 1.6, .06, C.STONE_DARK);
    for (const s of [-1, 1]) kit.group({ pos: [s * .38, .24, 0] }, () => {
      kit.lathe([[.26, 0], [.24, .7], [.2, .95], [.32, 1.05], [.32, 1.18], [0, 1.22]], { n: 12, capStart: true, color: l => l >= 3 ? TINT : C.IRON });
    });
    kit.tube([[-.38, .75, 0], [.38, .75, 0]], .1, { n: 6, color: C.IRON });
    kit.group({ pos: [0, .3, .45] }, () => {
      kit.ring(.36, .1, .1, C.STRAW, 16, PI / 2, 0, PI * 2, 0);
      kit.ring(.24, .1, .1, C.STRAW, 14, PI / 2, 0, PI * 2, .1);
    });
    kit.tube([[.6, .24, -.6], [.6, 2.1, -.6], [.3, 2.3, -.6]], .05, { n: 5, color: C.IRON });
    kit.lathe([[.1, 1.9], [.14, 2.0], [.14, 2.25], [.06, 2.36], [0, 2.4]].map(([r, y]) => [r, y - .2]), { n: 8, color: l => l === 1 ? C.FLAME : C.IRON });
  });

  // -------------------------------------------------------------------------
  // Shipwright's Slip (home islands, 9 x 6 x 9): a timber slipway with keel
  // blocks, the ribs of a hull on the cradle, a lumber stack, a sawhorse and a
  // small gantry crane. TINT is the paint pot / pennant.
  // -------------------------------------------------------------------------
  world('ShipwrightSlip', { smooth: 30, tint: '4AA8E8', kind: 'station', fit: [[-4.5, 0, -4.5], [4.5, 6, 4.5]] }, kit => {
    kit.bevelBox(0, .15, 0, 8.8, .3, 8.8, .06, { top: C.PLANK, side: C.BARK, bevel: C.STRAW, bottom: C.BARK_DARK });
    for (let k = 0; k < 4; k++) kit.bevelBox(0, .45, -3 + k * 2, 1.4, .3, .7, .05, C.BARK_DARK);
    kit.tube([[0, .7, -3.8], [0, .62, 3.8]], .14, { n: 6, color: C.BARK });
    for (let k = 0; k < 6; k++) {
      const z = -3.2 + k * 1.28;
      const w = 1.9 * Math.sin((k + .6) / 6.2 * PI);
      kit.tube([[-w, 3.0, z], [-w * .95, 1.8, z], [-w * .55, .95, z], [0, .7, z], [w * .55, .95, z], [w * .95, 1.8, z], [w, 3.0, z]], .1, { n: 4, color: C.PLANK });
    }
    for (const s of [-1, 1]) kit.tube([[s * 1.8, 2.9, -3.4], [s * 1.95, 3.0, 0], [s * 1.6, 2.85, 3.4]], .09, { n: 4, color: C.BRASS });
    // Gantry crane.
    for (const s of [-1, 1]) kit.bevelBox(s * 3.6, 3, 2.8, .3, 6, .3, .05, C.BARK);
    kit.bevelBox(0, 5.85, 2.8, 7.6, .3, .36, .05, C.BARK);
    kit.box(.8, 5.4, 2.8, .4, .5, .4, C.IRON);
    kit.tube([[.8, 5.15, 2.8], [.8, 3.4, 2.8]], .03, { n: 3, color: C.STRAW });
    // Lumber stack, sawhorse, paint pot and pennant.
    for (let r = 0; r < 3; r++) for (let k = 0; k < 3 - r; k++) kit.group({ pos: [-3.2 + k * .5 + r * .25, .45 + r * .42, -2.6], rot: [PI / 2, 0, 0] }, () => kit.lathe([[.2, -1.6], [.2, 1.6]], { n: 8, capStart: true, capEnd: true, color: C.TIMBER }));
    kit.bevelBox(3.2, 1.0, -2.6, 1.6, .2, .3, .04, C.PLANK);
    for (const s of [-1, 1]) kit.tube([[3.2 + s * .7, 1.0, -2.6], [3.2 + s * .9, .3, -2.4]], .06, { n: 4, color: C.BARK });
    kit.lathe([[.22, .3], [.24, .7], [.2, .74]], { n: 10, capStart: true, capEnd: true, capColor: TINT, color: C.IRON });
    kit.prism([[0, 0], [1.2, -.3], [0, -.6]].map(([x, y]) => [x + 3.75, y + 6.4]), .04, TINT, TINT_DARK, 2.8);
  });

  // -------------------------------------------------------------------------
  // Sky reef: a floating cluster of rock with coral fans, tube coral and
  // glowing anemone tips (TINT) clinging to it. Uniform fit 16 x 9 x 14.
  // -------------------------------------------------------------------------

  // -------------------------------------------------------------------------
  // Sky wreck: the broken fore half of a hull, listing, with snapped ribs, a
  // splintered mast and a torn pennant. Uniform fit 10 x 7 x 24.
  // -------------------------------------------------------------------------

  // -------------------------------------------------------------------------
  // Chart buoy (landmarks): a floating brass buoy with a striped float, a
  // lantern cage on a mast and a wind vane. Uniform fit 4 x 10 x 4.
  // -------------------------------------------------------------------------
  world('ChartBuoy', { smooth: 32, tint: 'C9A24E', kind: 'tower', range: 1400 }, kit => {
    kit.lathe([[0, 0], [1.2, .6], [1.9, 1.8], [2.0, 2.8], [1.7, 3.6], [1.0, 4.0], [.5, 4.1]], { n: 16, capEnd: true,
      color: l => l === 2 || l === 4 ? C.CRIMSON : l === 3 ? C.CLOTH : C.BRASS, capColor: C.BRASS });
    kit.ring(2.02, .14, .14, C.IRON, 24, PI / 2, 0, PI * 2, 2.8);
    kit.lathe([[.18, 4.0], [.16, 7.6], [.12, 8.0]], { n: 8, capEnd: true, color: C.IRON });
    kit.lathe([[.5, 7.6], [.56, 7.7], [.5, 8.8], [.3, 9.2], [0, 9.4]], { n: 10, color: l => l === 1 ? C.FLAME : C.BRASS });
    for (let k = 0; k < 4; k++) { const a = k * PI / 2; kit.box(Math.cos(a) * .52, 8.25, Math.sin(a) * .52, .06, 1.1, .06, C.IRON) }
    kit.tube([[0, 9.5, 0], [0, 10, 0]], .03, { n: 3, color: C.IRON });
    kit.prism([[0, 9.8], [1.0, 9.9], [.9, 9.6]], .03, TINT, TINT_DARK);
    for (let k = 0; k < 3; k++) { const a = k * 2 * PI / 3 + .4; kit.tube([[Math.cos(a) * 1.6, .9, Math.sin(a) * 1.6], [Math.cos(a) * 1.2, -1.2, Math.sin(a) * 1.2]], [.12, .04], { n: 4, color: C.MOSS }) }
  });
};
