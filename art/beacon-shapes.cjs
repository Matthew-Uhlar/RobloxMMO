// Travel beacons (docs/DEPTH-CONTRACT.md §44): the dais every travel beacon
// stands on, the floating aether crystal and armillary rings the client spins
// above it (beacons.client.lua), and the Skyward Vent pad in the same design
// language. Loaded by art/generate-props.cjs after the region kit; every shape
// is authored here from primitives with the deterministic hash. Units are studs
// at scale 1, +Y up, fronts face -Z. Extra meta:
//   exactTint: the forge keeps one template per exact Tint on desktop (beacon
//              channels and crystals carry their region's colour; phones still
//              share the nearest variant)
'use strict';
module.exports = ({ world, C, PI, hash }) => {
  const { TINT, TINT_DARK, TINT_LIGHT } = C;
  // Octagon with flat faces on the axes and diagonals: vertex radius for an apothem.
  const OCT = PI / 8, oct = a => a / Math.cos(OCT);
  const tangent = a => PI / 2 - a; // yaw that turns local +Z onto the direction a

  // -------------------------------------------------------------------------
  // Dais: an octagonal stepped plinth (brass-banded), a rune-ring inlay and a
  // glowing socket on top, eight inlaid channels on the lower step, and four
  // carved pylons on the diagonals whose brass arms arc inward and meet in a
  // crown over the crystal. Fit = the forge's declared ShapeBox (5 x 5.6 x 5).
  // -------------------------------------------------------------------------
  const DAIS_FIT = [[-2.5, 0, -2.5], [2.5, 5.6, 2.5]];
  const dais = (kit, m) => {
    // Plinth: base band, brass bevel, two carved steps and the marble top.
    kit.lathe([[oct(2.45), 0], [oct(2.45), .3], [oct(2.34), .38], [oct(2.22), .43], [oct(2.22), .64], [oct(2.04), .72], [oct(1.98), .95]], {
      n: 8, phase: OCT, capStart: true, capEnd: true, capColor: m.top,
      color: level => [m.dark, m.trim, m.light, m.stone, m.light, m.stone][level] ?? m.stone,
    });
    // Inlaid channels: a glowing strip on the diagonal faces of the lower step,
    // a rune tablet on the four cardinal faces.
    for (let i = 0; i < 8; i++) {
      const a = i * PI / 4;
      kit.group({ pos: [Math.cos(a) * 2.45, .15, Math.sin(a) * 2.45], rot: [0, tangent(a), 0] }, () => {
        if (i % 2) kit.box(0, 0, .015, .16, .22, .05, TINT);
        else { kit.box(0, 0, .015, .62, .2, .05, m.trim); kit.box(0, 0, .03, .4, .1, .03, TINT_LIGHT) }
      });
      if (i % 2) kit.group({ pos: [Math.cos(a) * 2.22, .54, Math.sin(a) * 2.22], rot: [0, tangent(a), 0] }, () => kit.box(0, 0, .015, .9, .05, .04, TINT_DARK));
    }
    // Rune rings on the top: a brass outer band, the glowing rune ring and its glyphs.
    kit.ring(1.78, .1, .06, m.trim, 20, PI / 2, 0, PI * 2, .95);
    kit.ring(1.42, .16, .06, TINT, 20, PI / 2, 0, PI * 2, .95);
    for (let i = 0; i < 8; i++) {
      const a = i * PI / 4 + PI / 8;
      kit.group({ pos: [Math.cos(a) * 1.08, .97, Math.sin(a) * 1.08], rot: [0, tangent(a), 0] }, () => kit.box(0, 0, 0, i % 2 ? .26 : .14, .05, .08, TINT_LIGHT));
    }
    // Socket: a brass cup with a glowing disc the crystal hovers over.
    kit.lathe([[.78, .92], [.84, 1.04], [.7, 1.2], [.5, 1.26]], { n: 10, capEnd: true, capColor: TINT_LIGHT, color: level => level === 1 ? m.trim : m.dark });
    // Pylons on the diagonals; local +Z points outward, -Z toward the crystal.
    for (let k = 0; k < 4; k++) {
      const a = PI / 4 + k * PI / 2;
      kit.group({ pos: [Math.cos(a) * 1.55, .95, Math.sin(a) * 1.55], rot: [0, tangent(a), 0] }, () => {
        kit.slab(0, .18, 0, .8, .8, .7, .7, .36, m.dark, m.trim);
        kit.slab(0, 1.61, 0, .56, .56, .38, .38, 2.5, m.stone, m.light);
        kit.box(0, 1.5, -.255, .12, 2.0, .05, TINT); // inner channel facing the crystal
        kit.box(0, 2.15, .245, .24, .5, .05, TINT_DARK); // outer rune plate
        kit.box(0, 2.15, .27, .1, .3, .03, TINT_LIGHT);
        kit.box(0, 2.62, 0, .45, .1, .45, m.trim);
        kit.jewel(0, 2.98, .17, .15, .26, .12, TINT_LIGHT);
        kit.tube([[0, 2.8, 0], [0, 3.2, .04], [0, 3.55, -.2], [0, 3.8, -.72], [0, 3.93, -1.18], [0, 3.96, -1.42]],
          [.13, .12, .11, .1, .085, .07], { n: 5, color: m.trim });
      });
    }
    // Crown where the arms meet: a brass ring, a finial and a hanging glint.
    kit.ring(.3, .12, .1, m.trim, 10, PI / 2, 0, PI * 2, 4.9);
    kit.lathe([[.2, 4.86], [.24, 5.02], [.12, 5.3], [0, 5.6]], { n: 8, capStart: true, color: level => level === 0 ? m.trim : m.top });
    kit.jewel(0, 4.62, 0, .1, .2, .1, TINT_LIGHT);
  };
  world('TravelBeacon', { smooth: 30, tint: '8EE6CB', fit: DAIS_FIT, kind: 'warp', exactTint: true }, kit =>
    dais(kit, { top: C.MARBLE, light: C.MARBLE, stone: C.STONE_LIGHT, dark: C.STONE, trim: C.BRASS }));
  world('TravelBeaconBasalt', { smooth: 30, tint: 'A58CE0', fit: DAIS_FIT, kind: 'warp', exactTint: true }, kit =>
    dais(kit, { top: C.STONE_DARK, light: C.STONE_DARK, stone: C.INK, dark: C.IRON, trim: C.BRASS }));

  // -------------------------------------------------------------------------
  // Aether crystal: a faceted bipyramid with alternating lit facets and four
  // satellite shards. Centred on its origin (the client bobs and spins it).
  // -------------------------------------------------------------------------
  world('TravelBeaconCrystal', { smooth: 0, tint: '8EE6CB', fit: [[-.55, -1.2, -.55], [.55, 1.2, .55]], kind: 'warp', exactTint: true }, kit => {
    kit.lathe([[0, -1.2], [.22, -.85], [.4, -.4], [.5, .05], [.47, .4], [.3, .85], [0, 1.2]], {
      n: 8, jitter: (level, i) => level > 0 && level < 6 ? 1 + (hash(level, i, 611) - .5) * .12 : 1,
      color: (level, i) => level <= 1 ? TINT_DARK : level === 3 ? (i % 2 ? TINT_LIGHT : TINT) : (i + level) % 3 === 0 ? TINT_LIGHT : TINT,
    });
    for (let k = 0; k < 4; k++) {
      const a = k * PI / 2 + PI / 4, y = k % 2 ? .35 : -.25;
      kit.group({ pos: [Math.cos(a) * .82, y, Math.sin(a) * .82], rot: [(k % 2 ? .25 : -.25), a, .3] }, () =>
        kit.lathe([[0, -.32], [.11, -.08], [.13, .12], [0, .4]], { n: 6, color: (level, i) => level === 1 && i % 2 ? TINT_LIGHT : level === 0 ? TINT_DARK : TINT }));
    }
    for (let i = 0; i < 4; i++) { const a = i * PI / 2; kit.jewel(Math.cos(a) * .48, .05, Math.sin(a) * .48, .05, .1, .05, C.GLINT) }
  });

  // -------------------------------------------------------------------------
  // Armillary: two crossed brass meridians and a tinted rune equator with
  // studs. Centred on its origin; the client turns it about +Y.
  // -------------------------------------------------------------------------
  world('TravelBeaconRings', { smooth: 25, tint: '8EE6CB', fit: [[-1.15, -1.15, -1.15], [1.15, 1.15, 1.15]], kind: 'warp', exactTint: true }, kit => {
    kit.group({ rot: [0, PI / 5, .35] }, () => kit.ring(1.05, .08, .06, C.BRASS, 24));
    kit.group({ rot: [0, -PI / 3, -.5] }, () => kit.ring(.92, .07, .05, C.BRASS, 22));
    kit.group({ rot: [.22, 0, 0] }, () => {
      kit.ring(1.12, .05, .07, TINT, 24, PI / 2);
      for (let i = 0; i < 6; i++) { const a = i * PI / 3; kit.jewel(Math.cos(a) * 1.12, 0, Math.sin(a) * 1.12, .07, .1, .07, i % 2 ? TINT_LIGHT : C.GLINT) }
    });
  });

  // -------------------------------------------------------------------------
  // Skyward Vent pad (§31): a carved stone ring with a brass rim, a rune ring
  // and radial channels on top, a spiral grille over the glowing updraft well,
  // a brass hub and four rune bollards. Fills the vent disk (8 x 1).
  // -------------------------------------------------------------------------
  world('SkywardVentPad', { smooth: 25, tint: '9BD18B', fit: [[-4, 0, -4], [4, 1, 4]], kind: 'warp', exactTint: true }, kit => {
    kit.lathe([[4, 0], [4, .36], [3.82, .46], [3.62, .52], [3.62, .74], [3.36, .82], [2.3, .82], [2.12, .62], [1.98, .36], [0, .36]], {
      n: 16, phase: PI / 16, capStart: true,
      color: (level, i) => [C.STONE, C.BRASS, C.STONE_LIGHT, C.STONE, C.STONE_LIGHT, C.STONE_LIGHT, C.STONE, C.STONE_DARK, TINT_LIGHT][level] ?? C.STONE,
    });
    kit.ring(2.85, .14, .05, TINT, 32, PI / 2, 0, PI * 2, .82);
    for (let i = 0; i < 8; i++) {
      const a = i * PI / 4 + PI / 8;
      kit.group({ pos: [Math.cos(a) * 3.05, .83, Math.sin(a) * 3.05], rot: [0, tangent(a), 0] }, () => kit.box(0, 0, 0, .1, .04, .5, TINT_DARK));
    }
    // Spiral grille: twelve pitched vanes from the hub to the well wall.
    for (let i = 0; i < 12; i++) {
      const a = i * PI / 6;
      kit.group({ pos: [Math.cos(a) * 1.25, .5, Math.sin(a) * 1.25], rot: [.5, -a, 0] }, () => kit.box(0, 0, 0, 1.5, .05, .22, C.IRON));
    }
    kit.lathe([[.55, .36], [.5, .6], [.3, .74], [0, .8]], { n: 10, color: level => level === 0 ? C.BRASS : C.IRON });
    kit.jewel(0, .82, 0, .14, .14, .14, TINT_LIGHT);
    for (let k = 0; k < 4; k++) {
      const a = PI / 4 + k * PI / 2;
      kit.group({ pos: [Math.cos(a) * 3.5, .52, Math.sin(a) * 3.5] }, () => {
        kit.lathe([[.2, 0], [.18, .3], [.11, .38]], { n: 6, capEnd: true, capColor: C.BRASS, color: C.BRASS });
        kit.jewel(0, .43, 0, .07, .05, .07, TINT_LIGHT);
      });
    }
  });
};
