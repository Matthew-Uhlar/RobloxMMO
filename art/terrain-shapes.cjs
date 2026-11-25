// Environment art pass (docs/DEPTH-CONTRACT.md §54): island dressing meshes —
// ground clutter (grass, flowers, pebbles, mushrooms, shards), rocks (moss
// stones, outcrops), shrubs (bushes, ferns, reeds), tree species per biome with
// a near and a far LOD (broadleaf, blossom, willow, spire pine, snowy spire
// pine, mushroom, crystal), cliff dressing (hanging roots, vine curtains, crystal
// veins) and satellite rocks. Loaded by art/generate-props.cjs into their own
// lazily decoded catalog (art/TerrainCatalog.lua, ReplicatedStorage.AetherTerrainArt);
// terrain.client.lua places them through the MeshForge "dress" pool.
//
// Rules (§54 QC A2-A5; the generator rejects a shape that breaks them):
//   * smooth: rings have >= 20 segments (>= 16 is the floor; 28-48 on hero
//     detail and wide fans, by placed size), elliptic sections are spread by
//     normal angle (`even`), profiles turn gently level to level (rounded rims
//     from capProfile, curves resampled from Beziers), thin tips stay open (a
//     hair-thin hole instead of a folded pole), blobs subdivide >= 2 (3 for
//     flattened forms) with continuous fbm displacement, never per-vertex jitter;
//   * per-vertex colour: colour comes from continuous fields of the face centre
//     (height ramps, crown gradients, smoothstep moss, snow on upward faces);
//     the forge diffuses it over the vertices of each material family
//     (art/generate-props.cjs FAMILY); `blend` joins moss / soil / snow / straw
//     to TINT so they fade into it instead of seaming;
//   * canopies carry `sphere` entries: the forge bends their shading normals
//     toward the crown's centre (one soft volume, not lumpy lobes).
// TINT is the species' region colour (leaves, petals, crystal, stone).
// Units are studs at scale 1, +Y up, origin on the ground at the base centre
// (cliff dressing: at the rim attachment, hanging -Y, facing -Z; satellites: at
// the top centre). meta.maxScale is the largest scale terrain.client.lua places.
'use strict';
module.exports = ({ terrain, C, PI, hash }) => {
  const { TINT, TINT_DARK, TINT_LIGHT } = C;
  const N = 24, WIDE = 28, HERO = 32;
  // Continuous 3D value noise and fbm (smooth; [-1, 1]).
  const lattice = (x, y, z, s) => hash(x + 4099 * y, z, s);
  const smooth = t => t * t * (3 - 2 * t);
  const noise3 = (x, y, z, s) => {
    const ix = Math.floor(x), iy = Math.floor(y), iz = Math.floor(z);
    const fx = smooth(x - ix), fy = smooth(y - iy), fz = smooth(z - iz);
    const l = (a, b, c) => lattice(ix + a, iy + b, iz + c, s);
    const lerp = (a, b, t) => a + (b - a) * t;
    return lerp(lerp(lerp(l(0, 0, 0), l(1, 0, 0), fx), lerp(l(0, 1, 0), l(1, 1, 0), fx), fy),
      lerp(lerp(l(0, 0, 1), l(1, 0, 1), fx), lerp(l(0, 1, 1), l(1, 1, 1), fx), fy), fz) * 2 - 1;
  };
  const fbm = (p, f, s, oct = 2) => { let a = 0, w = 1, t = 0; for (let k = 0; k < oct; k++) { a += w * noise3(p[0] * f + 17 * k, p[1] * f, p[2] * f, s + k); t += w; w *= .5; f *= 2; } return a / t; };
  const rnd = (a, b, s) => hash(a, b, s);
  const sstep = (e0, e1, x) => smooth(Math.min(1, Math.max(0, (x - e0) / (e1 - e0))));
  // Colour fields: lathe / tube callbacks get (level, segment, centre); blobs
  // get (normal, centre). Both read only the position (and normal).
  const ramp = (lo, hi, dark = TINT_DARK, mid = TINT, light = TINT_LIGHT) => (a, b, c) => { const y = c[1]; return y < lo ? dark : y > hi ? light : mid; };
  // A rounded closure: a pole reached through gently turning levels.
  const dome = (r, y, h, steps = 4) => Array.from({ length: steps }, (_, k) => { const a = (k + 1) / steps * PI / 2; return [k === steps - 1 ? 0 : r * Math.cos(a), y + h * Math.sin(a)]; });
  // A rounded cap profile (mushroom caps, petal cups, pine fans, islet tops):
  // a flat underside from r0 out to the rim, a rounded rim (arc of radius th,
  // <= 24 deg per level) and a parabolic dome of height `rise` meeting the rim
  // with the same tangent, closing in a pole.
  const capProfile = (r0, R, y, th, rise, domeSteps = 6, arcDeg = 18) => {
    const x0 = R - th, phi = Math.atan2(2 * rise, x0), pts = [[r0, y], [x0, y]];
    const a0 = -PI / 2, a1 = PI / 2 - phi, steps = Math.max(3, Math.ceil((a1 - a0) / (arcDeg * PI / 180)));
    for (let k = 1; k <= steps; k++) { const a = a0 + (a1 - a0) * k / steps; pts.push([x0 + th * Math.cos(a), y + th + th * Math.sin(a)]); }
    const [xe, ye] = pts[pts.length - 1], h = xe * Math.tan(phi) / 2;
    for (let k = 1; k <= domeSteps; k++) { const x = xe * (1 - k / domeSteps); pts.push([k === domeSteps ? 0 : x, ye + h * (1 - (x / xe) ** 2)]); }
    return pts;
  };
  // Quadratic Bezier resampled into k points (smooth branches and roots).
  const curve = (a, b, c, k = 5) => Array.from({ length: k }, (_, i) => { const t = i / (k - 1), u = 1 - t; return [0, 1, 2].map(q => u * u * a[q] + 2 * u * t * b[q] + t * t * c[q]); });

  // -------------------------------------------------------------------------
  // Grass, blades and stalks (clutter).
  // -------------------------------------------------------------------------
  // A wide blade: an elliptic section (even normals) tapering to a fine open
  // tip, leaning out along a smooth curve; root -> tip colour ramp.
  const blade = (kit, x, z, h, w, lean, yaw, s, leaf = false) => kit.group({ pos: [x, 0, z], rot: [0, yaw, 0] }, () =>
    kit.lathe([[w, -.06], [w * .95, h * .24], [w * .8, h * .5], [w * .55, h * .74], [w * .22, h * .93]], {
      n: N, sz: .6, even: true, phase: rnd(s, 1, 3) * .4,
      wobble: level => [lean * h * (level / 4) ** 2, 0],
      color: leaf ? ramp(h * .32, h * .7, C.LEAF_DARK, C.LEAF, C.LEAF) : ramp(h * .32, h * .7),
    }));
  const tuft = (kit, count, spread, hMin, hMax, seed, leaf = false) => {
    for (let k = 0; k < count; k++) {
      const a = k * 2.399 + rnd(k, 1, seed) * .5, d = spread * Math.sqrt((k + .5) / count);
      blade(kit, Math.cos(a) * d, Math.sin(a) * d, hMin + (hMax - hMin) * rnd(k, 2, seed), .1 + rnd(k, 3, seed) * .05, .2 + rnd(k, 4, seed) * .25,
        -a + (rnd(k, 5, seed) - .5) * .8, seed + k, leaf);
    }
  };
  terrain('GrassTuft', { smooth: 60, tint: '6FA956', kind: 'clutter', maxScale: 1.3 }, kit => tuft(kit, 6, .55, .6, 1.2, 901));
  terrain('MeadowGrass', { smooth: 60, tint: '7DB35C', kind: 'clutter', maxScale: 1.3, blend: [C.STRAW] }, kit => {
    tuft(kit, 5, 1.0, .9, 1.8, 911);
    for (let k = 0; k < 2; k++) {
      const a = k * 2.4 + .4, d = .45;
      kit.group({ pos: [Math.cos(a) * d, 0, Math.sin(a) * d], rot: [(rnd(k, 1, 912) - .5) * .3, 0, (rnd(k, 2, 912) - .5) * .3] }, () =>
        kit.lathe([[.04, -.05], [.036, 1.5], [.052, 1.62], [.075, 1.76], [.088, 1.92], [.075, 2.08], ...dome(.05, 2.16, .1, 2)], {
          n: N, color: (a2, b2, c) => c[1] > 1.6 ? C.STRAW : c[1] < .5 ? TINT_DARK : TINT,
        }));
    }
  });
  terrain('FlowerSprigs', { smooth: 60, tint: 'E58AB0', kind: 'clutter', maxScale: 1.3, blend: [C.GOLD] }, kit => {
    tuft(kit, 2, .5, .4, .7, 921, true);
    for (let k = 0; k < 2; k++) {
      const a = k * 2.399 + .3, d = .25 + .35 * rnd(k, 1, 922), h = .75 + rnd(k, 2, 922) * .5;
      const x = Math.cos(a) * d, z = Math.sin(a) * d, lean = (rnd(k, 3, 922) - .5) * .2;
      kit.group({ pos: [x, 0, z] }, () => kit.lathe([[.032, -.05], [.03, h * .5], [.026, h]], { n: N, wobble: level => [lean * level, 0], color: () => C.LEAF_DARK }));
      kit.group({ pos: [x + lean * 2, h - .02, z], rot: [(rnd(k, 4, 922) - .5) * .4, a, (rnd(k, 5, 922) - .5) * .4] }, () =>
        // Petal cup: five soft scallops (a smooth cosine of the angle), gold heart.
        kit.lathe(capProfile(.03, .25, -.03, .05, .06, 4, 18), {
          n: N, color: (l, i, c) => Math.hypot(c[0], c[2]) < .1 && c[1] > .02 ? C.GOLD : TINT,
        }));
    }
  });

  // -------------------------------------------------------------------------
  // Stones (clutter / rock): sub >= 2 (3 for flattened boulders), fbm-displaced,
  // smoothstep moss on top (blended into the stone, not seamed).
  // -------------------------------------------------------------------------
  const stoneField = (ry, moss) => (n, m) => {
    const up = m[1] / ry;
    if (moss && up > .3 + .25 * (1 - sstep(.4, .9, n[1]))) return C.MOSS;
    return up > .45 ? TINT_LIGHT : up < -.15 ? TINT_DARK : TINT;
  };
  const stone = (kit, x, y, z, rx, ry, rz, s, sub, moss) =>
    kit.blob(x, y, z, rx, ry, rz, { sub, seed: s, displace: p => 1 + .07 * fbm(p, 1.2, s), color: stoneField(ry, moss) });
  terrain('Pebbles', { smooth: 60, tint: '8C8F92', kind: 'clutter', maxScale: 1.4 }, kit => {
    for (let k = 0; k < 4; k++) {
      const a = k * 2.399, d = .3 + .6 * rnd(k, 1, 931), s = .16 + rnd(k, 2, 931) * .2;
      stone(kit, Math.cos(a) * d, s * .45, Math.sin(a) * d, s * 1.08, s * .88, s, 932 + k, 2, false);
    }
  });
  terrain('MossStone', { smooth: 60, tint: '858A8F', kind: 'rock', maxScale: 1.2, blend: [C.MOSS] }, kit => {
    stone(kit, 0, .35, 0, 1.0, .65, .8, 941, 3, true);
    stone(kit, .95, .2, .45, .35, .3, .33, 942, 2, true);
  });
  terrain('StoneOutcrop', { smooth: 60, tint: '7E8388', kind: 'rock', maxScale: 1.3, blend: [C.MOSS] }, kit => {
    stone(kit, 0, .9, 0, 1.7, 1.4, 1.3, 951, 3, true);
    stone(kit, 1.6, .5, .7, .9, .8, .8, 952, 2, true);
    stone(kit, -1.3, .4, .9, .7, .6, .62, 953, 2, true);
  });
  terrain('MushroomCluster', { smooth: 60, tint: 'B07AD6', kind: 'clutter', maxScale: 1.2 }, kit => {
    for (let k = 0; k < 3; k++) {
      const a = k * 2.399 + .5, d = k === 0 ? 0 : .4 + .3 * rnd(k, 1, 961), h = k === 0 ? .9 : .4 + rnd(k, 2, 961) * .4, r = h * .45;
      kit.group({ pos: [Math.cos(a) * d, 0, Math.sin(a) * d], rot: [(rnd(k, 3, 961) - .5) * .3, 0, (rnd(k, 4, 961) - .5) * .3] }, () => {
        kit.lathe([[r * .3, -.05], [r * .26, h * .5], [r * .22, h]], { n: N, color: () => C.CLOTH });
        kit.lathe(capProfile(r * .2, r, h - .03, r * .16, r * .42, 3, 20), {
          n: N, color: (l, i, c) => c[1] < h + r * .05 ? TINT_DARK : c[1] > h + r * .45 ? TINT_LIGHT : TINT,
        });
      });
    }
  });
  // Rounded crystal points: smooth shafts with a soft tip.
  const point = (kit, len, r, s) => kit.lathe([[r * .7, -.15], [r, len * .3], [r * .95, len * .6], [r * .62, len * .82], [r * .3, len * .94], [0, len]], {
    n: N, phase: rnd(s, 1, 1), color: (l, i, c) => c[1] > len * .55 ? TINT_LIGHT : c[1] < len * .15 ? TINT_DARK : TINT,
  });
  terrain('ShardCluster', { smooth: 60, tint: '8FE3FF', kind: 'clutter', maxScale: 1.2 }, kit => {
    kit.blob(0, .2, 0, .72, .58, .7, { sub: 2, seed: 971, displace: p => 1 + .06 * fbm(p, 1.2, 971), color: () => C.STONE_DARK });
    for (let k = 0; k < 4; k++) {
      const a = k * 2.399, len = 1.0 + rnd(k, 1, 972) * 1.1, r = .13 + rnd(k, 2, 972) * .1;
      kit.group({ pos: [Math.cos(a) * .3, .2, Math.sin(a) * .3], rot: [Math.sin(a) * .5, 0, -Math.cos(a) * .5] }, () => point(kit, len, r, 973 + k));
    }
  });

  // -------------------------------------------------------------------------
  // Shrubs.
  // -------------------------------------------------------------------------
  const foliageField = (cy, ry) => (n, m) => {
    const t = (m[1] - cy) / ry + .35 * n[1];
    return t > .45 ? TINT_LIGHT : t < -.35 ? TINT_DARK : TINT;
  };
  // A lobe of foliage: an fbm-displaced blob whose colour follows the crown's
  // vertical gradient (cy / ry of the whole crown, not of the lobe).
  const lobe = (kit, x, y, z, r, sub, s, cy, ry) =>
    kit.blob(x, y, z, r, r * .86, r, { sub, seed: s, displace: p => 1 + .06 * fbm(p, 1.2, s), color: (n, m) => foliageField(cy - y, ry)(n, m) });
  terrain('LeafyBush', { smooth: 60, tint: '5E9A4E', kind: 'shrub', maxScale: 1.3, sphere: [[0, .95, 0, 2.6, .5]] }, kit => {
    lobe(kit, 0, .9, 0, 1.2, 2, 1001, .95, 1.1);
    for (let k = 0; k < 4; k++) {
      const a = k * PI / 2 + .4;
      lobe(kit, Math.cos(a) * .9, .65 + rnd(k, 1, 1002) * .3, Math.sin(a) * .85, .7, 2, 1003 + k, .95, 1.1);
    }
  });
  terrain('Fern', { smooth: 60, tint: '4F8F45', kind: 'shrub', maxScale: 1.4 }, kit => {
    for (let k = 0; k < 6; k++) {
      const a = k * 2 * PI / 6 + rnd(k, 1, 1011) * .3, tilt = .8 + rnd(k, 2, 1011) * .25, len = 1.4 + rnd(k, 3, 1011) * .5;
      kit.group({ rot: [0, -a + PI / 2, 0] }, () => kit.group({ rot: [tilt, 0, 0] }, () =>
        kit.lathe([[.06, -.05], [.2, len * .1], [.32, len * .24], [.4, len * .42], [.38, len * .58], [.3, len * .74], [.16, len * .9]], {
          n: N, sz: .45, even: true, wobble: level => [0, -.012 * level * level],
          color: ramp(len * .2, len * .7),
        })));
    }
  });
  terrain('ReedClump', { smooth: 60, tint: '7C9A4E', kind: 'shrub', maxScale: 1.4 }, kit => {
    tuft(kit, 6, .7, 1.6, 2.8, 1021);
    for (let k = 0; k < 2; k++) {
      const a = k * 2.6 + .9, d = .35, h = 2.4 + rnd(k, 1, 1022) * .6;
      kit.group({ pos: [Math.cos(a) * d, 0, Math.sin(a) * d], rot: [(rnd(k, 2, 1022) - .5) * .2, 0, (rnd(k, 3, 1022) - .5) * .2] }, () => {
        kit.lathe([[.04, -.05], [.036, h - .5], [.06, h - .42], [.095, h - .3], [.11, h - .1], [.1, h + .12], ...dome(.07, h + .2, .14, 2)], {
          n: N, color: (l, i, c) => c[1] > h - .45 ? C.BARK : TINT_DARK,
        });
      });
    }
  });

  // -------------------------------------------------------------------------
  // Trees: near LOD (dense canopies, hero detail) and far LOD per species.
  // -------------------------------------------------------------------------
  // Bark trunk with a flared root foot that fades into the ground (open base).
  const trunk = (kit, r, top, s, { wobble, mid = [], dark = C.BARK_DARK, light = C.BARK, n = N } = {}) =>
    kit.lathe([[r * 1.5, -.3], [r * 1.32, .1], [r * 1.12, .5], [r * 1.02, 1.0], ...mid, [r * .6, top - .4], [r * .45, top]], {
      n, phase: rnd(s, 1, 1), wobble, jitter: (level, i) => 1 + .04 * Math.sin(3 * i * 2 * PI / n + s),
      color: (l, i, c) => c[1] < .7 ? dark : light,
    });
  // Branches: smooth Bezier tubes tapering into the crown (open, buried ends).
  const branch = (kit, a, b, c, r0, color = C.BARK) => { const pts = curve(a, b, c, 5); kit.tube(pts, pts.map((_, i) => r0 * (1 - i / pts.length * .55)), { n: N, color: () => color, capStart: false, capEnd: false }); };
  // A canopy cluster: a main crown (sub mainSub) wrapped by `lobes` lobes (sub 2)
  // on an upper-hemisphere spiral; one vertical gradient over the whole crown.
  const canopy = (kit, cx, cy, cz, R, lobes, s, mainSub, flat = 1) => {
    const ry = R * .8 * flat;
    kit.blob(cx, cy, cz, R * .78, R * .66 * flat, R * .78, { sub: mainSub, seed: s, displace: p => 1 + .06 * fbm(p, 1.2, s), color: foliageField(0, ry) });
    for (let k = 0; k < lobes; k++) {
      const a = k * 2.399 + rnd(k, 1, s) * .4, up = -.15 + .75 * ((k + .5) / lobes), d = R * .62 * Math.sqrt(1 - up * up * .6);
      lobe(kit, cx + Math.cos(a) * d, cy + up * R * .55 * flat, cz + Math.sin(a) * d, R * (.42 + .12 * rnd(k, 2, s)), 2, s + 10 + k, cy, ry);
    }
  };
  const tree = (name, meta, nearBuild, farBuild) => {
    terrain(name, { ...meta, lod: 'near', far: name + 'Far' }, nearBuild);
    terrain(name + 'Far', { ...meta, lod: 'far' }, farBuild);
  };
  const crownSphere = (cx, cy, cz, R) => [[cx, cy, cz, R * 1.5, .55]];
  // Broadleaf: a round, lobed oak-like crown on a stout flared trunk.
  tree('BroadleafTree', { smooth: 60, tint: '5E9C4C', kind: 'foliage', maxScale: 2.8, sphere: crownSphere(0, 9.4, 0, 4.2) }, kit => {
    trunk(kit, .7, 7.4, 1101, { mid: [[.66, 2.4], [.62, 3.8], [.58, 5.2], [.52, 6.4]] });
    branch(kit, [0, 5.0, 0], [1.4, 6.2, .3], [2.6, 7.8, .6], .3);
    branch(kit, [0, 5.4, 0], [-1.3, 6.5, -.4], [-2.4, 8.0, -.9], .28);
    branch(kit, [0, 5.8, 0], [-.2, 7.0, 1.2], [-.4, 8.4, 2.2], .26);
    canopy(kit, 0, 9.4, 0, 4.2, 9, 1105, 3);
  }, kit => {
    trunk(kit, .7, 7.4, 1101);
    canopy(kit, 0, 9.4, 0, 4.2, 2, 1105, 3);
  });
  // Blossom: a leaning twisted trunk under a wide, flat umbrella of bloom.
  tree('BlossomTree', { smooth: 60, tint: 'F2A7C3', kind: 'foliage', maxScale: 2.8, sphere: crownSphere(.7, 7.0, 0, 3.8) }, kit => {
    trunk(kit, .5, 5.6, 1201, { mid: [[.46, 2], [.42, 3.4], [.38, 4.6]], wobble: level => [Math.sin(level * .9) * .25 + level * .08, Math.cos(level * .7) * .12] });
    branch(kit, [.6, 4.4, 0], [2.0, 5.4, .4], [3.6, 6.2, .9], .22);
    branch(kit, [.5, 4.6, 0], [-1.2, 5.6, -.7], [-2.8, 6.4, -1.4], .2);
    branch(kit, [.6, 4.8, 0], [.4, 5.8, 1.6], [.1, 6.6, 3.0], .2);
    canopy(kit, .7, 7.0, 0, 3.8, 10, 1205, 3, .6);
  }, kit => {
    trunk(kit, .5, 5.6, 1201, { wobble: level => [Math.sin(level * .9) * .25 + level * .08, 0] });
    canopy(kit, .7, 7.0, 0, 3.8, 2, 1205, 3, .6);
  });
  // Willow: a domed crown spilling into a draped curtain with ragged strand tips.
  const curtainProfile = () => {
    const pts = [];
    for (let k = 0; k <= 6; k++) { const a = PI / 2 * (1 - k / 6); pts.push([1.8 + 3.3 * Math.cos(a), 7.2 + 3.6 * Math.sin(a)]); }
    for (let k = 1; k <= 4; k++) pts.push([5.1 - .08 * k, 7.2 - 1.05 * k]);
    return pts;
  };
  const curtain = (kit, n, s) => kit.lathe(curtainProfile(), {
    n, phase: .1,
    jitter: (level, i) => level >= 3 ? 1 + .03 * Math.sin(5 * i * 2 * PI / n + level * .3) : 1,
    lift: (level, i) => level >= 8 ? (level - 7) * .22 * (.5 + .5 * Math.sin(5 * i * 2 * PI / n + s)) : 0,
    color: (l, i, c) => c[1] > 9.6 ? TINT_LIGHT : c[1] < 4.6 ? TINT_DARK : TINT,
  });
  tree('WillowTree', { smooth: 60, tint: '7FAE5A', kind: 'foliage', maxScale: 2.8, sphere: crownSphere(0, 9.6, 0, 3.8) }, kit => {
    trunk(kit, .75, 8.4, 1301, { mid: [[.7, 2.4], [.64, 4], [.58, 5.6], [.52, 7.2]], wobble: level => [level * .05, 0] });
    branch(kit, [0, 6.6, 0], [1.6, 8.0, .3], [3.0, 8.8, .4], .26);
    branch(kit, [0, 6.8, 0], [-1.5, 8.2, -.6], [-2.8, 8.9, -.9], .26);
    canopy(kit, 0, 9.8, 0, 3.6, 7, 1304, 3, .7);
    curtain(kit, 48, 1305);
  }, kit => {
    trunk(kit, .75, 8.4, 1301);
    canopy(kit, 0, 9.8, 0, 3.6, 0, 1304, 3, .7);
    curtain(kit, 28, 1305);
  });
  // Spire pine: drooping branch fans with scalloped rims folding under in a
  // rounded lip, darker needle sub-rings beneath, irregular phase and tilt per
  // tier. The scallops (a smooth cosine of the angle) dip toward the rim only.
  const fan = (kit, r, y, n, t, s, sub, top) => kit.group({ pos: [0, y, 0], rot: [(rnd(t, 1, s) - .5) * .12, rnd(t, 2, s) * PI, (rnd(t, 3, s) - .5) * .12] }, () => {
    const prof = capProfile(r * .72, r, -.62, .08 + r * .06, .3 + r * .85, 5, 18), scallops = Math.max(4, Math.round(n / 7));
    const weight = prof.map(([x]) => (x / r) ** 2);
    kit.lathe(prof, {
      n, phase: rnd(t, 4, s), jitter: (level, i) => 1 + .05 * weight[level] * Math.cos(scallops * i * 2 * PI / n + t),
      lift: (level, i) => -.1 * weight[level] * (1 + Math.cos(scallops * i * 2 * PI / n + t)),
      color: (l, i, c) => c[1] > -.05 ? top : c[1] < -.5 ? TINT_DARK : TINT,
    });
    if (sub) kit.lathe(capProfile(r * .5, r * .8, -.95, .06 + r * .03, .25, 3, 18), { n, phase: rnd(t, 5, s) + .2, color: () => TINT_DARK });
  });
  const pine = (kit, n, tiers, s, sub, top) => {
    trunk(kit, .45, 13.6, 1401, { mid: [[.42, 3], [.36, 6], [.3, 9], [.24, 12]] });
    const list = tiers === 6 ? [[3.1, 3.0], [2.6, 5.5], [2.05, 8.0], [1.5, 10.3], [.95, 12.4], [.5, 14.3]]
      : [[3.0, 3.2], [2.3, 6.4], [1.6, 9.4], [.9, 12.2], [.45, 14.3]];
    list.forEach(([r, y], t) => fan(kit, r, y, n, t, s, sub && t < 3, top));
    kit.lathe([[.22, 14.9], [.17, 15.5], ...dome(.12, 15.7, .35, 3)], { n: N, color: () => top });
  };
  tree('SpirePine', { smooth: 60, tint: '3F7550', kind: 'foliage', maxScale: 2.8 }, kit => pine(kit, WIDE, 6, 1402, true, TINT_LIGHT), kit => pine(kit, N, 5, 1402, false, TINT_LIGHT));
  // Skyreach: the same pine under snow (white on upward faces, blended into the needles).
  tree('SnowPine', { smooth: 60, tint: '3F6F5A', kind: 'foliage', maxScale: 2.8, blend: [C.GLINT] }, kit => pine(kit, WIDE, 6, 1452, true, C.GLINT), kit => pine(kit, N, 5, 1452, false, C.GLINT));
  // Mushroom tree: a giant toadstool with a gill skirt and glowing spots.
  const toadstool = (kit, n, spots) => {
    kit.lathe([[1.5, -.3], [1.3, .15], [1.08, .6], [.94, 1.3], [.87, 2.6], [.84, 4.0], [.86, 5.0], [.92, 5.7], [1.0, 6.2]], {
      n, wobble: level => [Math.sin(level * .5) * .18, 0], color: (l, i, c) => c[1] < .6 ? C.STONE_DARK : C.CLOTH,
    });
    const cn = Math.max(n, 44);
    kit.lathe(capProfile(.95, 4.65, 6.0, .42, 2.6, 6, 18), {
      n: cn, jitter: (level, i) => level >= 2 ? 1 + .03 * Math.sin(5 * i * 2 * PI / cn) : 1,
      color: (l, i, c) => c[1] < 6.3 ? TINT_DARK : c[1] > 8.4 ? TINT_LIGHT : TINT,
    });
    for (let k = 0; k < spots; k++) {
      const a = k * 2.399, d = 1.2 + rnd(k, 1, 1503) * 2.2, y = 9.1 - d * d * .11;
      kit.blob(Math.cos(a) * d, y - .12, Math.sin(a) * d, .34, .28, .34, { sub: 2, seed: 1504 + k, color: () => C.GLINT });
    }
  };
  tree('MushroomTree', { smooth: 60, tint: '9C5FD0', kind: 'foliage', maxScale: 2.8 }, kit => {
    toadstool(kit, WIDE, 3);
    for (const [x, z, h] of [[1.9, .9, 1.3], [-1.6, -1.4, 1.0]]) kit.group({ pos: [x, 0, z] }, () => {
      kit.lathe([[.18, -.05], [.15, h * .7], [.14, h]], { n: N, color: () => C.CLOTH });
      kit.lathe(capProfile(.14, .58, h - .04, .1, .3, 4, 18), { n: N, color: (l, i, c) => c[1] < h + .02 ? TINT_DARK : TINT });
    });
  }, kit => toadstool(kit, N, 0));
  // Crystal tree: a stone trunk branching into clusters of soft crystal points.
  const crystalTree = (kit, perTip) => {
    trunk(kit, .6, 6.4, 1601, { mid: [[.56, 2.2], [.5, 3.6], [.44, 5]], dark: C.STONE_DARK, light: C.STONE });
    const tips = [[2.6, 7.4, .4], [-2.3, 7.8, -.9], [-.2, 8.3, 2.4], [.7, 8.9, -2.2], [.1, 9.6, .1]];
    tips.forEach(([x, y, z], k) => {
      branch(kit, [0, 4.6 + k * .25, 0], [x * .45, y - 1.6, z * .45], [x, y - .4, z], .24, C.STONE);
      for (let j = 0; j < perTip; j++) {
        const len = 1.7 + rnd(j, k, 1610) * 1.3, r = .26 + rnd(j, k, 1611) * .12;
        kit.group({ pos: [x, y - .5, z], rot: [(rnd(j, k, 1612) - .5) * 1.1, j * 2.1, (rnd(j, k, 1613) - .5) * 1.1] }, () => point(kit, len, r, 1614 + j + k));
      }
    });
  };
  tree('CrystalTree', { smooth: 60, tint: '9DE6FF', kind: 'foliage', maxScale: 2.8 }, kit => crystalTree(kit, 3), kit => crystalTree(kit, 1));

  // -------------------------------------------------------------------------
  // Cliff dressing: origin = the attachment at the rim, wall at z = 0.
  // -------------------------------------------------------------------------
  terrain('HangingRoots', { smooth: 60, tint: '6A4A32', kind: 'cliff', maxScale: 1.4, blend: [C.SOIL, C.MOSS] }, kit => {
    for (let k = 0; k < 5; k++) {
      const x = (k - 2) * .55 + (rnd(k, 1, 1701) - .5) * .3, len = 2.6 + rnd(k, 2, 1701) * 3.2, out = .35 + rnd(k, 3, 1701) * .4;
      const pts = curve([x, .2, .2], [x * 1.06, -len * .45, -out * 1.2], [x * 1.1, -len, -out * .7], 6);
      kit.tube(pts, pts.map((_, i) => .2 * (1 - i / 6) + .02), { n: N, color: (l, i, c) => c[1] > -.5 ? C.SOIL : TINT, capStart: false, capEnd: false });
    }
    kit.blob(0, -.15, -.15, 1.5, .45, .45, { sub: 3, seed: 1702, displace: p => 1 + .06 * fbm(p, 1.5, 1702), color: (n, m) => m[1] > .1 ? C.MOSS : C.SOIL });
  });
  terrain('VineCurtain', { smooth: 60, tint: '4E8A44', kind: 'cliff', maxScale: 1.4 }, kit => {
    for (let k = 0; k < 5; k++) {
      const x = (k - 2) * .6, len = 3 + rnd(k, 1, 1801) * 3;
      const pts = curve([x, .15, .05], [x + .12, -len * .5, -.45], [x, -len, -.25], 6);
      kit.tube(pts, pts.map((_, i) => .07 - i * .009), { n: 16, color: () => TINT_DARK, capStart: false, capEnd: false });
      lobe(kit, x + .1, -len * .55, -.42, .34, 2, 1802 + k, -len * .5, len * .5);
    }
    lobe(kit, 0, 0, -.25, 1.2, 2, 1810, 0, 1);
  });
  terrain('CrystalVein', { smooth: 60, tint: 'A58BFF', kind: 'cliff', maxScale: 1.4 }, kit => {
    kit.blob(0, -1.4, .1, 1.9, 1.3, .6, { sub: 3, seed: 1901, displace: p => 1 + .06 * fbm(p, 1.5, 1901), color: () => C.STONE_DARK });
    for (let k = 0; k < 5; k++) {
      const x = (k - 2) * .7 + (rnd(k, 1, 1902) - .5) * .3, y = -.7 - rnd(k, 2, 1902) * 1.4, len = .8 + rnd(k, 3, 1902) * 1.1, r = .14 + rnd(k, 4, 1902) * .1;
      kit.group({ pos: [x, y, -.15], rot: [-PI / 2 + (rnd(k, 5, 1902) - .5) * .6, 0, (rnd(k, 6, 1902) - .5) * .6] }, () => point(kit, len, r, 1903 + k));
    }
  });

  // -------------------------------------------------------------------------
  // Satellite rocks: a rounded top on a strata keel tapering into a spire.
  // -------------------------------------------------------------------------
  const satellite = (kit, seed, r, depth, grassy) => {
    const levels = [];
    for (let k = 0; k <= 14; k++) { const t = k / 14; levels.push([k === 14 ? 0 : r * (.03 + .97 * Math.cos(t * PI / 2) ** 1.3), -.2 - depth * t ** 1.25]); }
    kit.lathe(levels, {
      n: HERO, phase: rnd(seed, 1, 1), jitter: (level, i) => 1 + .05 * Math.sin(3 * i * 2 * PI / HERO + level * .25 + seed) * Math.min(1, level / 4),
      color: (l, i, c) => { const b = Math.floor(-c[1] * 1.1 + 9) % 3; return c[1] > -.45 ? (grassy ? C.SOIL : TINT_LIGHT) : b === 0 ? TINT_LIGHT : b === 1 ? TINT : TINT_DARK; },
    });
    kit.lathe(capProfile(r * .9, r * 1.02, -.3, .24, .5, 5, 18), {
      n: HERO, jitter: (level, i) => 1 + .03 * Math.sin(5 * i * 2 * PI / HERO + seed),
      color: (l, i, c) => grassy ? (Math.hypot(c[0], c[2]) > r * .92 ? C.LEAF_DARK : C.LEAF) : TINT_LIGHT,
    });
  };
  terrain('SatelliteRock', { smooth: 60, tint: '6B7380', kind: 'satellite', range: 1200, maxScale: 2.6, blend: [C.SOIL] }, kit => {
    satellite(kit, 2001, 4, 7.5, true);
    lobe(kit, 1.4, .85, .6, .8, 2, 2002, .8, .9);
    stone(kit, -1.5, .6, -.9, .7, .55, .62, 2004, 2, true);
    for (let k = 0; k < 3; k++) {
      const a = k * 2.1 + .5, x = Math.cos(a) * 3.0, z = Math.sin(a) * 3.0, len = 1.6 + rnd(k, 1, 2006) * 1.4;
      const pts = curve([x, -.8, z], [x * 1.08, -.8 - len * .5, z * 1.08], [x * 1.04, -.8 - len, z * 1.04], 5);
      kit.tube(pts, pts.map((_, i) => .12 - i * .025), { n: 16, color: () => C.BARK, capStart: false, capEnd: false });
    }
  });
  terrain('SatelliteRockBare', { smooth: 60, tint: '5E6470', kind: 'satellite', range: 1200, maxScale: 2.6 }, kit => {
    satellite(kit, 2101, 3.2, 6.5, false);
    stone(kit, .8, .65, -.5, .9, .75, .8, 2102, 2, false);
    stone(kit, -1.0, .5, .7, .6, .5, .55, 2104, 2, false);
  });
};
