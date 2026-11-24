// Runebinding (docs/DEPTH-CONTRACT.md §49): the Binding Altar every rune is
// bound at, the guardian portals and the Rift Guardian monolith of the Glyph
// Rift. Loaded by art/generate-props.cjs after the beacon kit; authored from
// primitives with the deterministic hash. Units are studs at scale 1, +Y up,
// fronts face -Z. exactTint: each altar / portal keeps its rune's own colour
// (TINT faces are the emissive glyph inlays; runes.client.lua adds the glow).
// Every curved surface is a smooth-shaded lathe of >= 24 segments; fit boxes
// equal the mesh bounds, so a host sized to the fit box shows the whole mesh.
'use strict';
module.exports = ({ world, C, PI, hash }) => {
  const { TINT, TINT_DARK, TINT_LIGHT } = C;
  const SEG = 24, HALF = PI / SEG, oct = a => a / Math.cos(HALF);
  const tangent = a => PI / 2 - a;

  // A carved rune glyph: a vertical stave with two angled branches and a
  // dot, inlaid on a face (local +Z out of the face). Emissive tint strokes.
  const glyph = (kit, scale, variant) => {
    kit.box(0, 0, 0, .07 * scale, .62 * scale, .04, TINT_LIGHT);
    const t = variant % 3;
    kit.group({ pos: [0, (t === 0 ? .14 : -.06) * scale, 0], rot: [0, 0, .7] }, () => kit.box(.12 * scale, 0, 0, .3 * scale, .06 * scale, .04, TINT_LIGHT));
    kit.group({ pos: [0, (t === 2 ? .2 : -.18) * scale, 0], rot: [0, 0, -.7] }, () => kit.box(-.12 * scale, 0, 0, .3 * scale, .06 * scale, .04, TINT));
    kit.jewel(0, .4 * scale, .01, .06 * scale, .06 * scale, .03, TINT_LIGHT);
  };

  // -------------------------------------------------------------------------
  // Binding Altar: a stepped octagonal plinth (brass-banded basalt) with a
  // glowing rune ring, a tapered altar block carved with a glyph on each face,
  // a dished basin holding a glowing pool, and two crescent horns rising from
  // the back that cradle the space where the keystone floats. Fit 5 x 4.2 x 5.
  // -------------------------------------------------------------------------
  const ALTAR_FIT = [[-2.5, 0, -2.5], [2.5, 4.2, 2.5]];
  world('BindingAltar', { smooth: 30, tint: 'C38BFF', fit: ALTAR_FIT, kind: 'warp', exactTint: true }, kit => {
    kit.lathe([[oct(2.5), 0], [oct(2.5), .26], [oct(2.4), .34], [oct(2.28), .4], [oct(2.28), .62], [oct(2.08), .7], [oct(2.0), .9]], {
      n: SEG, phase: HALF, capStart: true, capEnd: true, capColor: C.STONE_DARK,
      color: level => [C.INK, C.BRASS, C.STONE_DARK, C.INK, C.STONE_DARK, C.STONE][level] ?? C.STONE_DARK,
    });
    // Rune ring on the plinth top, and channels on the diagonal faces of the lower step.
    kit.ring(1.86, .12, .05, TINT, 40, PI / 2, 0, PI * 2, .92);
    for (let i = 0; i < 8; i++) {
      const a = i * PI / 4 + PI / 8;
      kit.group({ pos: [Math.cos(a) * 2.5, .13, Math.sin(a) * 2.5], rot: [0, tangent(a), 0] }, () => {
        kit.box(0, 0, .015, .5, .16, .05, i % 2 ? TINT_DARK : C.BRASS);
        if (i % 2 === 0) kit.box(0, 0, .03, .3, .07, .03, TINT_LIGHT);
      });
    }
    // Altar block: tapered, brass-capped, one glyph tablet per face.
    kit.slab(0, 1.75, 0, 2.5, 2.5, 2.0, 2.0, 1.7, C.STONE_DARK, C.INK);
    kit.slab(0, 2.66, 0, 2.2, 2.2, 2.3, 2.3, .12, C.BRASS);
    for (let f = 0; f < 4; f++) {
      const a = f * PI / 2;
      const r = 1.13;
      kit.group({ pos: [Math.cos(a) * r, 1.72, Math.sin(a) * r], rot: [-.15, tangent(a), 0] }, () => {
        kit.box(0, 0, -.01, .78, 1.08, .06, C.INK);
        kit.box(0, 0, .01, .66, .96, .04, TINT_DARK);
        kit.group({ pos: [0, 0, .04] }, () => glyph(kit, 1.15, f));
      });
    }
    // Basin: a dished brass bowl with the glowing pool.
    kit.lathe([[1.05, 2.72], [1.12, 2.86], [1.0, 2.96], [.86, 2.92], [.7, 2.86]], { n: SEG, capEnd: true, capColor: TINT_LIGHT,
      color: level => level < 2 ? C.BRASS : C.IRON });
    kit.ring(.74, .06, .04, TINT, 32, PI / 2, 0, PI * 2, 2.9);
    // Crescent horns from the back corners, tips inward, with rune jewels.
    for (const side of [-1, 1]) {
      kit.tube([[side * 1.0, 2.7, .9], [side * 1.45, 3.2, 1.05], [side * 1.6, 3.7, .7], [side * 1.35, 4.05, .15], [side * .95, 4.1, -.2]],
        [.2, .18, .15, .11, .07], { n: 10, color: C.BRASS });
      kit.jewel(side * .92, 4.08, -.22, .09, .12, .09, TINT_LIGHT);
      kit.group({ pos: [side * 1.5, 3.45, .92], rot: [0, side * .6, 0] }, () => kit.box(0, 0, 0, .1, .4, .06, TINT));
    }
  });

  // -------------------------------------------------------------------------
  // Guardian portal: a basalt arch on a stepped sill, brass-banded pillars with
  // glyph columns, an arched lintel and a keystone gem, and a tinted veil with
  // a rune ring (the portal's element). Fit 4.22 x 6.96 x 1.6 (front -Z).
  // -------------------------------------------------------------------------
  world('GuardianPortal', { smooth: 30, tint: 'C38BFF', fit: [[-2.11, 0, -.8], [2.11, 6.96, .8]], kind: 'warp', exactTint: true }, kit => {
    kit.slab(0, .2, 0, 4.2, 1.6, 4.0, 1.45, .4, C.INK, C.STONE_DARK);
    for (const side of [-1, 1]) {
      kit.slab(side * 1.65, 2.6, 0, .8, .9, .66, .76, 4.4, C.STONE_DARK, C.STONE);
      kit.slab(side * 1.65, .58, 0, .92, 1.0, .9, .98, .36, C.BRASS);
      kit.slab(side * 1.65, 4.86, 0, .86, .96, .8, .9, .14, C.BRASS);
      for (let g = 0; g < 3; g++) kit.group({ pos: [side * 1.65, 1.5 + g * 1.15, -.39] }, () => glyph(kit, .75, g + (side > 0 ? 1 : 0)));
    }
    // Arched lintel (half ring) and the keystone.
    const arc = [];
    for (let i = 0; i <= 8; i++) { const t = PI * i / 8; arc.push([Math.cos(t) * 1.65, 4.9 + Math.sin(t) * 1.55, 0]) }
    kit.tube(arc, arc.map(() => .34), { n: 12, color: C.STONE_DARK });
    const band = arc.map(([x, y]) => [x * 1.0, y, -.3]);
    kit.tube(band, band.map(() => .08), { n: 8, color: C.BRASS });
    kit.jewel(0, 6.62, -.2, .28, .34, .2, TINT_LIGHT);
    // Veil: tinted panel filling the arch, with a rune ring and inner glyph.
    kit.box(0, 3.4, .05, 2.5, 4.6, .06, TINT_DARK);
    kit.group({ pos: [0, 4.2, -.02] }, () => kit.ring(.95, .1, .05, TINT, 32));
    kit.group({ pos: [0, 4.2, -.04] }, () => glyph(kit, 1.6, 2));
  });

  // -------------------------------------------------------------------------
  // Rift Guardian: an eight-faceted aether monolith on a stepped basalt base,
  // banded with glowing glyph rings and girdled by two brass armillaries with
  // rune studs. Fit 6 x 14 x 6.
  // -------------------------------------------------------------------------
  world('RiftMonolith', { smooth: 35, tint: 'C38BFF', fit: [[-3, 0, -3], [3, 14, 3]], kind: 'warp', exactTint: true }, kit => {
    kit.lathe([[oct(3), 0], [oct(3), .4], [oct(2.85), .5], [oct(2.6), .56], [oct(2.6), 1.0], [oct(2.3), 1.1], [oct(2.2), 1.5]], {
      n: SEG, phase: HALF, capStart: true, capEnd: true, capColor: C.INK,
      color: level => [C.INK, C.BRASS, C.STONE_DARK, C.INK, C.STONE_DARK, C.STONE][level] ?? C.INK,
    });
    kit.ring(2.45, .14, .06, TINT, 40, PI / 2, 0, PI * 2, 1.52);
    // The crystal: eight facets, banded light / dark, tapering to a point.
    kit.lathe([[1.3, 1.5], [1.55, 3.2], [1.6, 6.5], [1.4, 9.8], [.95, 12.2], [0, 14]], {
      n: 8, phase: PI / 8, capStart: true, capColor: TINT_DARK,
      color: (level, i) => level === 1 && i % 2 ? TINT_LIGHT : level === 3 ? TINT_LIGHT : (i + level) % 3 === 0 ? TINT : TINT_DARK,
    });
    // Glyph bands on the faces.
    for (let i = 0; i < 8; i++) {
      const a = i * PI / 4;
      kit.group({ pos: [Math.cos(a) * 1.6, 5.2, Math.sin(a) * 1.6], rot: [0, tangent(a), 0] }, () => glyph(kit, 1.4, i));
    }
    // Armillaries with rune studs.
    kit.group({ pos: [0, 7.2, 0], rot: [.25, 0, .15] }, () => {
      kit.ring(2.6, .12, .1, C.BRASS, 40, PI / 2);
      for (let i = 0; i < 6; i++) { const a = i * PI / 3; kit.jewel(Math.cos(a) * 2.6, 0, Math.sin(a) * 2.6, .14, .16, .14, i % 2 ? TINT_LIGHT : C.GLINT) }
    });
    kit.group({ pos: [0, 10.2, 0], rot: [-.3, .5, -.1] }, () => kit.ring(2.0, .1, .08, C.BRASS, 32, PI / 2));
    kit.ring(2.2, .08, .05, TINT, 32, PI / 2, 0, PI * 2, 3.2);
  });
};
