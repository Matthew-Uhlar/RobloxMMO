// World Art pass 2 (docs/DEPTH-CONTRACT.md §40): the modular building kit.
// Loaded by art/generate-props.cjs after the world and region shapes. Every
// building is one forged mesh authored from the same parts (stone plinths,
// timber framing over plaster, stone or log walls, arched plank doors,
// shuttered windows with glass panes and window boxes, jettied upper storeys,
// steep shingled / slate / thatched roofs with dormers and chimneys,
// balconies and awnings), so a whole house costs one template and one server
// part. Walk-in halls are hollow shells (real door and window openings, plank
// floors, ceiling ties) furnished by separate interior meshes.
//
// Frame: studs, +Y up, origin on the ground at the footprint centre, the
// street front faces -Z (the forge's convention). TINT is the roof (shingle,
// slate or thatch trim) so one shape serves every region's roof colour.
//
// Returns the kit table the world script builds from (written into
// world.server.lua between the GENERATED BUILDINGS markers):
//   kind   "facade" (solid: one collider = the wall block w x h x d),
//          "walkin" (hollow: floor, walls with a door gap; wall t, door u/w/h),
//          "interior" (furnishing set; host = the counter collider `counter`)
//   fit    the mesh's authored box (the forge maps it 1:1 onto ShapeBox)
//   windows {x, y, z, w, h, ry}: centre of each glass pane's outer face and the
//          yaw that turns -Z onto its outward normal (lit at night, §35/§40)
//   door   {x, z, w, h, ry}: the street door (walk-ins: the opening)
'use strict';
module.exports = ({ world, C, PI, hash, worldShapes }) => {
  const { TINT, TINT_DARK, TINT_LIGHT } = C;
  const KIT = {};
  const r3 = v => Math.round(v * 1000) / 1000;
  const rotY = (ry, [x, y, z]) => { const c = Math.cos(ry), s = Math.sin(ry); return [x * c + z * s, y, -x * s + z * c] };
  const pick = (seed, i, list) => list[Math.floor(hash(i, seed, 7) * list.length)];

  // Faces of a W x D block centred on (0, z0): x/z of the wall plane and the yaw.
  const faces = (W, D, z0 = 0) => ({
    front: { x: 0, z: z0 - D / 2, ry: 0 }, back: { x: 0, z: z0 + D / 2, ry: PI },
    right: { x: W / 2, z: z0, ry: -PI / 2 }, left: { x: -W / 2, z: z0, ry: PI / 2 },
  });
  const on = (b, f, fn) => b.kit.group({ pos: [f.x, 0, f.z], rot: [0, f.ry, 0] }, fn);
  const at = (f, u, v, g) => { const p = rotY(f.ry, [u, v, -g]); return [p[0] + f.x, p[1], p[2] + f.z] };

  // --- Face pieces (face-local: u along the wall, v up, wall surface z = 0, out = -Z).
  const post = (b, f, u, y0, y1, w = .3) => on(b, f, () => b.kit.box(u, (y0 + y1) / 2, -.07, w, y1 - y0, .16, C.TIMBER));
  const beam = (b, f, u0, u1, y, h = .26) => on(b, f, () => b.kit.box((u0 + u1) / 2, y, -.08, u1 - u0, h, .18, C.TIMBER));
  const brace = (b, f, u0, y0, u1, y1) => on(b, f, () => {
    const len = Math.hypot(u1 - u0, y1 - y0);
    b.kit.box((u0 + u1) / 2, (y0 + y1) / 2, -.07, .24, len, .15, C.TIMBER, Math.atan2(u0 - u1, y1 - y0));
  });
  // X panel (two braces) filling a rectangle.
  const cross = (b, f, u0, y0, u1, y1) => { brace(b, f, u0, y0, u1, y1); brace(b, f, u1, y0, u0, y1) };
  // Window: frame, glass, mullion + transom, sill, lintel; optional shutters
  // (colour), a planter with flowers, a pointed arch head.
  const win = (b, f, u, v, w, h, o = {}) => {
    const k = b.kit;
    // o.open = wall thickness: a window through a hollow hall's wall. The
    // frame is four bars (not a backing plate) and the pane sits in the wall's
    // middle, so the window reads as glass from inside too.
    const gz = o.open ? o.open / 2 : -.15, front = o.open ? o.open / 2 - .03 : -.17;
    on(b, f, () => {
      if (o.open) {
        for (const s of [-1, 1]) {
          k.box(u, v + s * (h / 2 + .085), -.07, w + .34, .17, .14, o.frame ?? C.TIMBER);
          k.box(u + s * (w / 2 + .085), v, -.07, .17, h, .14, o.frame ?? C.TIMBER);
        }
        k.box(u, v, gz, w, h, .06, C.GLASS);
        k.box(u, v, front - .04, .09, h, .06, o.frame ?? C.TIMBER);
      } else {
        k.box(u, v, -.07, w + .34, h + .34, .14, o.frame ?? C.TIMBER);
        k.box(u, v, -.15, w, h, .04, C.GLASS_DARK);
        k.box(u, v, -.19, .09, h, .06, o.frame ?? C.TIMBER);
      }
      if (o.transom !== false && !o.open) k.box(u, v + h * .14, -.19, w, .09, .06, o.frame ?? C.TIMBER);
      k.box(u, v - h / 2 - .13, -.2, w + .5, .14, .36, o.sill ?? C.STONE_LIGHT);
      if (o.lintel) k.box(u, v + h / 2 + .15, -.16, w + .56, .2, .26, o.frame ?? C.TIMBER);
      if (o.shutters) for (const s of [-1, 1]) {
        k.box(u + s * (w / 2 + .2 + w * .25), v, -.12, w * .48, h + .04, .07, o.shutters);
      }
      if (o.box) {
        const y = v - h / 2 - .45;
        k.box(u, y, -.36, w + .24, .4, .46, C.PLANK);
        k.box(u, y + .26, -.36, w + .1, .14, .38, C.LEAF_DARK);
        for (let i = 0; i < 3; i++) k.jewel(u + (i - 1) * w * .34, y + .42, -.38 - (i % 2) * .08, .17, .17, .15, pick(o.box, i, [C.ROSE, C.FLAME, C.LAVENDER, C.GOLD, C.CLOTH]));
      }
      if (o.arch) k.prism([[-w / 2 - .17, 0], [w / 2 + .17, 0], [w * .3, w * .32], [0, w * .45], [-w * .3, w * .32]].map(([x, y]) => [x + u, y + v + h / 2 + .05]), .16, o.frame ?? C.TIMBER, o.frame ?? C.TIMBER, -.07);
    });
    b.windows.push([...at(f, u, v, -front).map(r3), r3(w), r3(h), r3(f.ry)]);
  };
  // Arched plank door with a stone surround, iron straps, a ring pull and a step.
  const archOutline = (w, h, n = 6) => {
    const pts = [[-w / 2, 0], [w / 2, 0]];
    for (let i = 0; i <= n; i++) { const a = i * PI / n; pts.push([Math.cos(a) * w / 2, h - w / 2 + Math.sin(a) * w / 2]) }
    return pts;
  };
  const door = (b, f, u, w, h, o = {}) => {
    const k = b.kit, y0 = o.y0 ?? 0;
    on(b, f, () => {
      const outer = archOutline(w + .6, h + .3), inner = archOutline(w, h);
      k.prism(outer.map(([x, y]) => [x + u, y + y0]), .2, o.surround ?? C.STONE_LIGHT, o.surround ?? C.STONE, -.06);
      k.prism(inner.map(([x, y]) => [x + u, y + y0]), .12, o.leaf ?? C.PLANK, C.BARK, -.2);
      for (const s of [-1, 1]) k.box(u + s * w / 6, y0 + (h - w / 4) / 2, -.27, .06, h - w / 4, .04, C.BARK);
      for (const y of [.25, .7]) k.box(u, y0 + (h - .2) * y, -.28, w * .92, .14, .05, C.IRON);
      k.jewel(u + w * .3, y0 + h * .45, -.32, .1, .1, .06, C.BRASS);
      if (y0 > .05) k.box(u, y0 / 2, -.45, w + .9, y0, .9, C.STONE_LIGHT);
    });
    b.door = { x: r3(at(f, u, 0, 0)[0]), z: r3(at(f, u, 0, 0)[2]), w: r3(w), h: r3(h), ry: r3(f.ry) };
  };
  // Open doorway for walk-in halls: timber jambs and lintel, carved corner
  // brackets, a stone threshold and both plank leaves swung back inside.
  const doorway = (b, f, u, w, h, t, o = {}) => {
    const k = b.kit;
    on(b, f, () => {
      for (const s of [-1, 1]) {
        k.box(u + s * (w / 2 + .2), h / 2, t / 2 - .05, .4, h, t + .3, o.frame ?? C.TIMBER);
        k.prism([[0, 0], [-s * .9, 0], [0, -.9]].map(([x, y]) => [u + s * w / 2 + x, y + h]), .3, o.frame ?? C.TIMBER, o.frame ?? C.TIMBER, -.05);
        k.group({ pos: [u + s * (w / 2 - .1), 0, t + .1], rot: [0, s * 1.35, 0] }, () => {
          k.box(-s * w / 4, (h - .3) / 2, 0, w / 2, h - .3, .14, o.leaf ?? C.PLANK);
          for (const y of [.25, .7]) k.box(-s * w / 4, (h - .3) * y, -.09, w / 2 - .1, .14, .05, C.IRON);
        });
      }
      k.box(u, h + .25, t / 2 - .05, w + 1.2, .5, t + .3, o.frame ?? C.TIMBER);
      k.box(u, .06, t / 2, w + .4, .12, t + .6, C.STONE_LIGHT);
    });
    const p = at(f, u, 0, 0);
    b.door = { x: r3(p[0]), z: r3(p[2]), w: r3(w), h: r3(h), ry: r3(f.ry) };
  };
  // Stone plinth (bevelled) with proud dressed stones along two faces.
  const plinth = (b, W, D, h, seed, z0 = 0) => {
    const k = b.kit;
    k.bevelBox(0, h / 2, z0, W + .4, h, D + .4, .08, { top: C.STONE_LIGHT, side: C.STONE, bevel: C.STONE_LIGHT, bottom: C.STONE_DARK });
    for (let i = 0; i < 6; i++) {
      const front = i < 4, t = front ? -W / 2 + .9 + i * (W - 1.8) / 3 : -D / 3 + (i - 4) * D / 1.5;
      const x = front ? t : (i % 2 ? 1 : -1) * (W / 2 + .2), z = front ? z0 - D / 2 - .2 : z0 + t;
      k.box(x, h * (.35 + hash(i, seed, 1) * .3), z, front ? .9 : .14, h * .42, front ? .14 : .9, hash(i, seed, 2) < .5 ? C.STONE_DARK : C.STONE_LIGHT);
    }
  };
  // Gable roof, ridge along X at (y ridge, z0): deck, overlapping shingle
  // courses (each tilted so its lower edge stands proud), ridge cap,
  // bargeboards and fascias. Returns the slope (for dormers / chimneys).
  const gableRoof = (b, o) => {
    const k = b.kit, { w, d, eave, rise, ox = .7, oz = .8, th = .28, rows = 7, z0 = 0, seed = 1 } = o;
    const hs = d / 2, A = Math.atan2(rise, hs), L = (hs + oz) / Math.cos(A), ridge = eave + rise, W2 = w + 2 * ox;
    const shade = o.shade ?? ((j, s) => hash(j, s + 2, seed) < .2 ? TINT_DARK : TINT);
    for (const s of [-1, 1]) k.group({ pos: [0, ridge, z0], rot: [s * A, 0, 0] }, () => {
      k.box(0, -th / 2, s * L / 2, W2, th, L, C.TIMBER);
      const step = L / rows;
      for (let j = 0; j < rows; j++) {
        const zc = s * (L - (j + .5) * step);
        // Courses alternate in height, so every course line reads as a step.
        k.box(0, .065 + (j % 2) * .07, zc, W2 + .04, .13, step + .02, shade(j, s));
      }
      for (const e of [-1, 1]) k.box(e * (W2 / 2 + .06), -.05, s * L / 2, .14, .42, L + .1, C.TIMBER);
      k.box(0, -.18, s * (L - .05), W2 + .2, .36, .14, C.TIMBER);
    });
    k.group({ pos: [0, ridge + .12, z0], rot: [PI / 4, 0, 0] }, () => k.box(0, 0, 0, W2 + .2, .36, .36, TINT_DARK));
    for (const e of [-1, 1]) k.jewel(e * (W2 / 2 + .05), ridge + .45, z0, .14, .32, .14, C.BRASS);
    return { A, ridge, z0, hs, at: z => ridge - Math.abs(z - z0) * Math.tan(A) };
  };
  // Gable-end wall (triangle) at x = side * xw with king post, collar and braces.
  const gableEnd = (b, side, xw, eave, rise, hs, z0, o = {}) => {
    const k = b.kit, f = { x: side * xw, z: z0, ry: side > 0 ? -PI / 2 : PI / 2 };
    on(b, f, () => {
      k.prism([[-hs, eave], [hs, eave], [0, eave + rise]], .3, o.fill ?? C.PLASTER, o.fill ?? C.PLASTER, .15);
      if (o.timber !== false) {
        k.box(0, eave + rise * .45, -.07, .26, rise * .9, .15, C.TIMBER);
        k.box(0, eave + rise * .42, -.08, hs * 1.1, .24, .17, C.TIMBER);
      }
    });
    if (o.window) win(b, f, 0, eave + rise * .2, o.window[0], o.window[1], { lintel: false, transom: false });
  };
  // Dormer on the front slope (roof `r`) at x = dx: cheeks, a small gable roof and a window.
  const dormer = (b, r, dx, dw = 2.4, dh = 2.2, seed = 3) => {
    const k = b.kit, zf = r.z0 - r.hs * .5, y0 = r.at(zf) - .35, depth = (dh + .35) / Math.tan(r.A) + .2;
    k.box(dx, y0 + dh / 2, zf + depth / 2, dw, dh, depth, C.PLASTER);
    const B = Math.atan2(1.1, dw / 2 + .2);
    for (const s of [-1, 1]) k.group({ pos: [dx, y0 + dh + 1.1, zf + depth / 2 - .15], rot: [0, 0, -s * B] }, () => {
      const l = (dw / 2 + .4) / Math.cos(B);
      k.box(s * l / 2, -.1, 0, l, .2, depth + .6, TINT);
    });
    on(b, { x: dx, z: zf, ry: 0 }, () => k.prism([[-dw / 2, dh], [dw / 2, dh], [0, dh + 1.05]].map(([x, y]) => [x, y + y0]), .2, C.PLASTER, C.TIMBER, .1));
    win(b, { x: dx, z: zf, ry: 0 }, 0, y0 + dh * .5, dw * .5, dh * .6, { transom: false, sill: C.TIMBER, box: seed });
  };
  // Chimney: a stack through the roof with a string course, a cap and two pots.
  const pots = (b, x, z, y1) => { for (const s of [-1, 1]) b.kit.group({ pos: [x + s * .3, 0, z] }, () => b.kit.lathe([[.17, y1 + .2], [.2, y1 + .55], [.14, y1 + .75], [.17, y1 + .82]], { n: 6, capEnd: true, capColor: C.INK, color: C.CRIMSON })) };
  const stack = (b, x, z, y0, y1, o = {}) => {
    const k = b.kit, w = o.w ?? 1.3;
    k.box(x, (y0 + y1) / 2, z, w, y1 - y0, w * .8, o.color ?? C.BRICK);
    k.box(x, y1 - (y1 - y0) * .3, z, w + .1, .18, w * .8 + .1, C.STONE_DARK);
    k.bevelBox(x, y1 + .1, z, w + .3, .2, w * .8 + .3, .05, C.STONE_LIGHT);
    pots(b, x, z, y1);
  };
  // Balcony on a face: deck on brackets, posts, top rail and balusters.
  const balcony = (b, f, u, y, w, depth = 1.2) => on(b, f, () => {
    const k = b.kit;
    k.box(u, y, -depth / 2, w, .2, depth, C.PLANK);
    for (const s of [-1, 1]) k.box(u + s * (w / 2 - .3), y - .45, -.35, .2, .7, .7, C.TIMBER);
    k.box(u, y + 1.05, -depth + .06, w, .14, .14, C.TIMBER);
    for (const s of [-1, 1]) k.box(u + s * (w / 2 - .07), y + 1.05 / 2 + .1, -depth / 2, .14, .14, depth, C.TIMBER);
    const n = Math.max(3, Math.round(w / .8));
    for (let i = 0; i <= n; i++) k.box(u - w / 2 + .07 + i * (w - .14) / n, y + .55, -depth + .06, .1, .9, .1, C.TIMBER);
  });
  // Striped awning on a face (TINT / cloth) with a scalloped valance.
  const awning = (b, f, u, y, w, depth = 1.7, stripe = C.CLOTH) => on(b, f, () => {
    const k = b.kit, n = Math.max(4, Math.round(w / .7)), sw = w / n, A = .45;
    k.group({ pos: [u, y, 0], rot: [A, 0, 0] }, () => {
      for (let i = 0; i < n; i++) k.box(-w / 2 + (i + .5) * sw, 0, -depth / 2, sw, .08, depth, i % 2 ? stripe : TINT);
    });
    const yv = y - Math.sin(A) * depth, zv = -Math.cos(A) * depth;
    for (let i = 0; i < n; i++) k.prism([[-sw / 2, 0], [sw / 2, 0], [0, -.34]].map(([x, yy]) => [x + u - w / 2 + (i + .5) * sw, yy + yv]), .05, i % 2 ? stripe : TINT, TINT_DARK, zv);
    for (const s of [-1, 1]) k.box(u + s * (w / 2 - .05), y - .1, -depth * .5, .07, .07, depth * 1.05, C.IRON);
  });

  // Building wrapper: authors the mesh and records the kit entry.
  const building = (name, meta, spec, build) => {
    let entry;
    world(name, { smooth: 35, kind: 'building', tint: meta.tint, interior: spec.kind === 'interior' || undefined }, kit => {
      const b = { kit, windows: [], door: null };
      build(b);
      entry = { kind: spec.kind, w: spec.w, d: spec.d, h: spec.h, windows: b.windows };
      if (b.door) entry.door = b.door;
      for (const key of ['t', 'floor', 'counter', 'opening', 'region']) if (spec[key] !== undefined) entry[key] = spec[key];
    });
    // Fit = the authored mesh bounds, so ShapeBox = fit size maps 1:1.
    const data = worldShapes[name], lo = [1e9, 1e9, 1e9], hi = [-1e9, -1e9, -1e9];
    for (const p of data.vertices) for (let a = 0; a < 3; a++) { lo[a] = Math.min(lo[a], p[a]); hi[a] = Math.max(hi[a], p[a]) }
    entry.fit = [lo.map(r3), hi.map(r3)];
    entry.tint = meta.tint;
    KIT[name] = entry;
    return entry;
  };

  // =========================================================================
  // Facade houses (solid; one collider block w x h x d).
  // =========================================================================
  // TimberHouse: two storeys, plaster between dark timbers on a stone plinth,
  // jettied upper floor on corbels, steep shingled gable roof, front dormer,
  // brick chimney, shuttered windows with flower boxes, arched plank door.
  building('TimberHouse', { tint: 'B5523B' }, { kind: 'facade', w: 12, d: 10, h: 10 }, b => {
    const k = b.kit, W = 12, D = 10, P = .8, G = 5.4, J = .6, E = 10;
    plinth(b, W, D, P, 11);
    k.box(0, (P + G) / 2, 0, W, G - P, D, C.PLASTER);
    k.box(0, G + .15, -J / 2, W + .4, .3, D + J + .3, C.TIMBER);
    k.box(0, (G + .3 + E) / 2, -J / 2, W + .3, E - G - .3, D + J, C.PLASTER);
    for (const x of [-4.6, -1.6, 1.6, 4.6]) k.box(x, G - .3, -D / 2 - .22, .3, .55, .5, C.TIMBER);
    const g = faces(W, D), u = faces(W + .3, D + J, -J / 2);
    // Ground front: door, two shuttered windows, corner and door posts.
    for (const x of [-5.85, -3.9, -1.3, 5.85]) post(b, g.front, x, P, G);
    door(b, g.front, -2.6, 2.2, 3.9, { y0: P });
    win(b, g.front, 1.5, 3.2, 1.7, 1.9, { shutters: C.DEEP, box: 12 });
    win(b, g.front, 4.1, 3.2, 1.7, 1.9, { shutters: C.DEEP, box: 13 });
    // Upper front: three windows over X-braced sill panels.
    for (const x of [-6.0, -1.95, 1.95, 6.0]) post(b, u.front, x, G + .3, E);
    beam(b, u.front, -6.1, 6.1, E - .14);
    for (const x of [-3.95, 0, 3.95]) {
      win(b, u.front, x, 8.15, 1.5, 1.9, { shutters: x === 0 ? undefined : C.DEEP, box: x === 0 ? 14 : undefined });
      cross(b, u.front, x - .8, G + .45, x + .8, 6.65);
    }
    // Sides and back.
    for (const side of [g.right, g.left]) {
      for (const x of [-4.85, 4.85]) post(b, side, x, P, G);
      win(b, side, -1.2, 3.2, 1.5, 1.8, { transom: false });
    }
    for (const side of [u.right, u.left]) {
      for (const x of [-5.15, -1, 1, 5.15]) post(b, side, x, G + .3, E);
      beam(b, side, -5.3, 5.3, E - .14);
      win(b, side, 2.6, 8.0, 1.4, 1.8, { transom: false });
    }
    win(b, g.back, 2.5, 3.2, 1.5, 1.8, { transom: false, lintel: false });
    for (const x of [-3, 3]) win(b, u.back, x, 8.0, 1.4, 1.8, { transom: false, lintel: false });
    const r = gableRoof(b, { w: W + .3, d: D + J, eave: E, rise: 6.6, z0: -J / 2, rows: 7, seed: 11 });
    for (const s of [-1, 1]) gableEnd(b, s, (W + .3) / 2, E, 6.6, (D + J) / 2, -J / 2, { window: s > 0 ? [1.0, 1.3] : undefined });
    dormer(b, r, -2.6, 2.4, 2.1, 15);
    stack(b, 3.4, 2.2, r.at(2.2) - 1, r.ridge + 1.6);
  });

  // TimberTownhouse: a narrow three-storey row house, front-gabled, with a
  // balcony on the second floor and a carved bargeboard gable to the street.
  building('TimberTownhouse', { tint: '2F6F8F' }, { kind: 'facade', w: 8, d: 10, h: 14 }, b => {
    const k = b.kit, W = 8, D = 10, P = .7, S1 = 5.2, S2 = 9.6, E = 14;
    plinth(b, W, D, P, 21);
    k.box(0, (P + S1) / 2, 0, W, S1 - P, D, C.PLASTER);
    k.box(0, S1 + .14, -.25, W + .3, .28, D + .8, C.TIMBER);
    k.box(0, (S1 + .28 + S2) / 2, -.25, W + .2, S2 - S1 - .28, D + .5, C.PLASTER);
    k.box(0, S2 + .14, -.5, W + .5, .28, D + 1.2, C.TIMBER);
    k.box(0, (S2 + .28 + E) / 2, -.5, W + .4, E - S2 - .28, D + 1, C.PLASTER);
    const g = faces(W, D), m = faces(W + .2, D + .5, -.25), t = faces(W + .4, D + 1, -.5);
    for (const x of [-3.85, 3.85, -.55]) post(b, g.front, x, P, S1);
    door(b, g.front, -2.1, 2.0, 3.8, { y0: P, leaf: C.DEEP });
    win(b, g.front, 1.8, 3.1, 2.1, 2.0, { shutters: C.CRIMSON, box: 22 });
    for (const x of [-3.95, -1.2, 1.2, 3.95]) post(b, m.front, x, S1 + .28, S2);
    win(b, m.front, 0, 7.6, 1.6, 2.2, {});
    for (const x of [-2.55, 2.55]) cross(b, m.front, x - .7, S1 + .5, x + .7, S2 - .4);
    balcony(b, m.front, 0, S1 + .5, W - .6, 1.1);
    for (const x of [-4.05, 4.05]) post(b, t.front, x, S2 + .28, E);
    for (const x of [-2, 2]) win(b, t.front, x, 12.0, 1.4, 1.9, { shutters: C.CRIMSON, box: 23 + x });
    beam(b, t.front, -4.2, 4.2, E - .14);
    for (const [side, ss] of [[g.right, 1], [g.left, -1]]) {
      for (const x of [-4.85, 4.85]) post(b, side, x, P, S1);
      win(b, side, 1.5, 3.1, 1.4, 1.7, { transom: false });
    }
    for (const side of [m.right, m.left]) { for (const x of [-5.1, 5.1]) post(b, side, x, S1 + .28, S2); win(b, side, -1.5, 7.4, 1.4, 1.8, { transom: false }) }
    for (const side of [t.right, t.left]) { for (const x of [-5.35, 5.35]) post(b, side, x, S2 + .28, E); win(b, side, 1.8, 11.8, 1.3, 1.7, { transom: false }) }
    win(b, m.back, 0, 7.4, 1.5, 1.8, { transom: false, lintel: false });
    // Front gable: ridge along Z (the roof built turned a quarter).
    const rise = 6.2;
    k.group({ rot: [0, PI / 2, 0], pos: [0, 0, -.5] }, () => {
      const r = gableRoof(b, { w: D + 1, d: W + .4, eave: E, rise, ox: .9, oz: .7, rows: 7, seed: 21 });
    });
    for (const s of [-1, 1]) {
      const f = s < 0 ? { x: 0, z: -.5 - (D + 1) / 2, ry: 0 } : { x: 0, z: -.5 + (D + 1) / 2, ry: PI };
      on(b, f, () => {
        k.prism([[-(W + .4) / 2, E], [(W + .4) / 2, E], [0, E + rise]], .3, C.PLASTER, C.PLASTER, .15);
        k.box(0, E + rise * .42, -.07, .26, rise * .84, .15, C.TIMBER);
        k.box(0, E + 1.0, -.08, W * .8, .24, .17, C.TIMBER);
        // Carved bargeboard scallops along the street gable.
        if (s < 0) for (const e of [-1, 1]) for (let i = 1; i <= 4; i++) {
          const t2 = i / 5, x = e * (W + .4) / 2 * (1 - t2), y = E + rise * t2;
          k.jewel(x, y - .25, -.25, .18, .18, .1, C.TIMBER);
        }
      });
      if (s < 0) win(b, f, 0, E + 2.6, 1.3, 1.6, { transom: false, arch: true, lintel: false });
    }
    stack(b, 2.2, 3.5, E + 2, E + rise + 1.4, { w: 1.1 });
  });

  // TimberShopfront: a merchant's house: a glazed shop window with goods on
  // display under a striped awning (TINT), a plastered upper floor with an
  // oriel bay and a red-tiled roof with a dormer.
  building('TimberShopfront', { tint: 'D9A441' }, { kind: 'facade', w: 12, d: 10, h: 10 }, b => {
    const k = b.kit, W = 12, D = 10, P = .6, G = 5.4, E = 10;
    plinth(b, W, D, P, 31);
    k.box(0, (P + G) / 2, 0, W, G - P, D, C.PLASTER);
    k.box(0, G + .15, -.3, W + .4, .3, D + .9, C.TIMBER);
    k.box(0, (G + .3 + E) / 2, -.3, W + .2, E - G - .3, D + .6, C.PLASTER);
    const g = faces(W, D), u = faces(W + .2, D + .6, -.3);
    for (const x of [-5.85, -2.2, 5.85]) post(b, g.front, x, P, G);
    beam(b, g.front, -6, 6, G - .2, .34);
    door(b, g.front, -4.0, 2.0, 3.8, { y0: P, leaf: C.CRIMSON });
    // Shop window: wide glazed bay with a stall board of goods behind it.
    on(b, g.front, () => {
      k.box(1.8, 1.25, -.5, 7.0, 1.3, 1.0, C.PLANK);
      k.box(1.8, 1.95, -.5, 7.3, .14, 1.15, C.TIMBER);
      for (let i = 0; i < 6; i++) k.jewel(-1.0 + i * 1.1, 2.3, -.62, .3, .3, .26, pick(31, i, [C.ROSE, C.FLAME, C.GOLD, C.MINT, C.LAVENDER]));
    });
    win(b, g.front, 1.8, 3.55, 6.6, 2.4, { lintel: false, sill: C.TIMBER });
    for (const x of [-.4, 1.8, 4.0]) on(b, g.front, () => k.box(x, 3.55, -.2, .1, 2.4, .07, C.TIMBER));
    awning(b, g.front, .9, G - .45, 10.2, 1.9);
    // Upper: oriel bay window in the middle, side windows with boxes.
    on(b, u.front, () => {
      k.box(0, 7.7, -.5, 3.4, 3.0, 1.0, C.PLASTER);
      k.box(0, 6.05, -.55, 3.7, .3, 1.15, C.TIMBER);
      k.box(0, 9.35, -.55, 3.7, .3, 1.15, C.TIMBER);
      k.group({ pos: [0, 5.9, -.55] }, () => k.lathe([[1.0, 0], [.55, -.6], [0, -.95]], { n: 6, capStart: true, color: C.TIMBER, sz: .6, phase: PI / 6 }));
    });
    win(b, { x: 0, z: -D / 2 - .3 - 1.0, ry: 0 }, 0, 7.7, 2.4, 2.2, { lintel: false, sill: C.TIMBER });
    for (const x of [-4.2, 4.2]) win(b, u.front, x, 7.9, 1.5, 1.9, { shutters: C.NAVY, box: 33 + x });
    for (const x of [-6.0, -2.1, 2.1, 6.0]) post(b, u.front, x, G + .3, E);
    beam(b, u.front, -6.1, 6.1, E - .14);
    for (const side of [g.right, g.left]) { for (const x of [-4.85, 4.85]) post(b, side, x, P, G); win(b, side, 0, 3.2, 1.5, 1.8, { transom: false }) }
    for (const side of [u.right, u.left]) { for (const x of [-5.1, 5.1]) post(b, side, x, G + .3, E); win(b, side, 1.2, 7.9, 1.4, 1.8, { transom: false }) }
    win(b, u.back, 0, 7.9, 1.5, 1.8, { transom: false, lintel: false });
    const r = gableRoof(b, { w: W + .2, d: D + .6, eave: E, rise: 6.4, z0: -.3, rows: 6, seed: 31, shade: (j, s) => hash(j, s, 31) < .25 ? C.BRICK : C.CRIMSON });
    for (const s of [-1, 1]) gableEnd(b, s, (W + .2) / 2, E, 6.4, (D + .6) / 2, -.3, { window: s < 0 ? [1.0, 1.3] : undefined });
    dormer(b, r, 2.8, 2.4, 2.1, 34);
    stack(b, -3.6, 2.0, r.at(2.0) - 1, r.ridge + 1.5);
  });

  // StoneCottage: rubble-stone walls with dressed quoins, a slate roof (TINT),
  // a deep-set door under a stone hood, a gable chimney and a dormer.
  building('StoneCottage', { tint: '56677A' }, { kind: 'facade', w: 11, d: 9, h: 7 }, b => {
    const k = b.kit, W = 11, D = 9, E = 7;
    k.bevelBox(0, E / 2, 0, W, E, D, .12, { top: C.STONE, side: C.STONE, bevel: C.STONE_LIGHT, bottom: C.STONE_DARK });
    // Quoins and a scatter of proud stones.
    for (const x of [-1, 1]) for (const z of [-1, 1]) for (let i = 0; i < 5; i++) {
      const y = .7 + i * 1.3, long = i % 2 === 0;
      k.box(x * (W / 2 + .06) - x * (long ? .45 : .3), y, z * (D / 2 + .06) - z * (long ? .3 : .45), long ? 1.0 : .7, .6, long ? .7 : 1.0, C.STONE_LIGHT);
    }
    for (let i = 0; i < 10; i++) {
      const x = -W / 2 + 1.4 + hash(i, 41, 1) * (W - 2.8), y = .6 + hash(i, 41, 2) * (E - 1.4);
      if (Math.abs(x + 2.4) < 1.6 && y < 4.8) continue;
      k.box(x, y, -D / 2 - .05, .7 + hash(i, 41, 3) * .5, .4, .14, hash(i, 41, 4) < .5 ? C.STONE_DARK : C.STONE_LIGHT);
    }
    const g = faces(W, D);
    door(b, g.front, -2.4, 2.1, 3.9, { surround: C.STONE_LIGHT, leaf: C.TIMBER });
    on(b, g.front, () => { k.box(-2.4, 4.6, -.45, 3.4, .25, .9, C.STONE_LIGHT); for (const s of [-1, 1]) k.box(-2.4 + s * 1.5, 4.25, -.4, .3, .5, .7, C.STONE_LIGHT) });
    win(b, g.front, 2.3, 3.0, 1.8, 1.9, { shutters: C.MOSS, box: 42, frame: C.BARK_DARK });
    for (const side of [g.right, g.left]) win(b, side, 0, 3.0, 1.5, 1.7, { transom: false, frame: C.BARK_DARK });
    win(b, g.back, -2, 3.0, 1.5, 1.7, { transom: false, lintel: false, frame: C.BARK_DARK });
    const r = gableRoof(b, { w: W, d: D, eave: E, rise: 5.8, rows: 8, seed: 41, ox: .5, oz: .7 });
    for (const s of [-1, 1]) gableEnd(b, s, W / 2, E, 5.8, D / 2, 0, { fill: C.STONE, timber: false, window: s < 0 ? [.9, 1.2] : undefined });
    dormer(b, r, 2.3, 2.2, 2.0, 43);
    stack(b, W / 2 - .5, 0, E - 1, r.ridge + 1.2, { color: C.STONE, w: 1.5 });
  });

  // ThatchCottage: a low timber-and-plaster cottage under a deep straw thatch
  // with a rolled ridge and an eyebrow over the door (TINT: shutters and door).
  building('ThatchCottage', { tint: '3C8C7E' }, { kind: 'facade', w: 11, d: 9, h: 6 }, b => {
    const k = b.kit, W = 11, D = 9, P = .6, E = 6;
    plinth(b, W, D, P, 51);
    k.box(0, (P + E) / 2, 0, W, E - P, D, C.PLASTER);
    const g = faces(W, D);
    for (const side of [g.front, g.back]) { for (const x of [-5.35, -1.6, 1.6, 5.35]) post(b, side, x, P, E); beam(b, side, -5.5, 5.5, E - .2); beam(b, side, -5.5, 5.5, P + .15) }
    for (const side of [g.right, g.left]) { for (const x of [-4.35, 4.35]) post(b, side, x, P, E); beam(b, side, -4.5, 4.5, E - .2); cross(b, side, -4.1, P + .3, -2.3, E - .4) }
    door(b, g.front, 0, 2.0, 3.8, { y0: P, leaf: TINT });
    for (const x of [-3.5, 3.5]) win(b, g.front, x, 3.3, 1.6, 1.7, { shutters: TINT, box: 52 + x });
    for (const side of [g.right, g.left]) win(b, side, 1.4, 3.3, 1.4, 1.6, { transom: false, shutters: TINT });
    win(b, g.back, 0, 3.3, 1.5, 1.6, { transom: false, lintel: false });
    // Thatch: thick rounded slabs, a rolled ridge, ragged eave courses.
    const rise = 5.6, A = Math.atan2(rise, D / 2), L = (D / 2 + 1.2) / Math.cos(A), ridge = E + rise;
    for (const s of [-1, 1]) k.group({ pos: [0, ridge, 0], rot: [s * A, 0, 0] }, () => {
      k.bevelBox(0, -.35, s * L / 2, W + 1.6, .7, L, .3, { top: C.STRAW, side: C.STRAW, bevel: C.SOIL, bottom: C.BARK });
      for (let j = 0; j < 4; j++) k.bevelBox(0, .12, s * (L - .5 - j * L / 4.2), W + 1.7 - j * .1, .3, .9, .12, j % 2 ? C.STRAW : C.GOLD);
    });
    for (const s of [-1, 1]) on(b, { x: s * W / 2, z: 0, ry: s > 0 ? -PI / 2 : PI / 2 }, () => k.prism([[-D / 2, E], [D / 2, E], [0, E + rise]], .3, C.PLASTER, C.PLASTER, .15));
    k.group({ pos: [0, ridge + .1, 0], rot: [0, 0, PI / 2] }, () => k.lathe([[.55, -W / 2 - .9], [.62, -W / 4], [.6, W / 4], [.55, W / 2 + .9]], { n: 8, capStart: true, capEnd: true, color: (l, i) => i % 2 ? C.STRAW : C.GOLD }));
    for (let i = 0; i < 6; i++) k.box(-W / 2 + 1 + i * (W - 2) / 5, ridge + .55, 0, .12, .12, 1.3, C.BARK);
    stack(b, -3.2, 2.0, ridge - 2.4, ridge + 1.2, { color: C.STONE, w: 1.2 });
  });

  // LogLodge: a mountain lodge of stacked logs with notched corners, a
  // covered porch on posts, a steep shingled roof (TINT) and a stone chimney.
  building('LogLodge', { tint: '4E7A48' }, { kind: 'facade', w: 12, d: 10, h: 7.6 }, b => {
    const k = b.kit, W = 12, D = 10, E = 7.6;
    k.bevelBox(0, .35, 0, W + .4, .7, D + .4, .1, { top: C.STONE_LIGHT, side: C.STONE, bevel: C.STONE_LIGHT, bottom: C.STONE_DARK });
    k.box(0, (E + .7) / 2, 0, W - .4, E - .7, D - .4, C.TIMBER);
    // Logs: front/back along X, sides along Z, with notched overlaps.
    const n = 9, lr = (E - .7) / n / 2;
    for (let i = 0; i < n; i++) {
      const y = .7 + lr + i * 2 * lr, col = i % 3 === 2 ? C.PLANK : C.BARK;
      for (const z of [-1, 1]) k.group({ pos: [0, y, z * (D / 2 - lr * .6)], rot: [0, 0, PI / 2] }, () => k.lathe([[lr, -W / 2 - .35], [lr * 1.05, W / 2 + .35]], { n: 6, capStart: true, capEnd: true, capColor: C.PLANK, color: col, phase: i }));
      if (i % 2 === 0) for (const x of [-1, 1]) k.box(x * (W / 2 - lr * .6), y, 0, lr * 1.6, lr * 1.9, D - .2, col);
    }
    const g = faces(W, D);
    door(b, g.front, 0, 2.2, 4.0, { y0: .7, surround: C.TIMBER, leaf: C.PLANK });
    for (const x of [-3.8, 3.8]) win(b, g.front, x, 3.4, 1.7, 1.8, { shutters: TINT, box: 61 + x, frame: C.BARK_DARK });
    for (const side of [g.right, g.left]) win(b, side, -1.5, 3.4, 1.5, 1.7, { transom: false, frame: C.BARK_DARK });
    win(b, g.back, 2, 3.4, 1.5, 1.7, { transom: false, lintel: false, frame: C.BARK_DARK });
    // Porch: deck, posts, a lean-to roof.
    k.box(0, .55, -D / 2 - 1.2, W - 1, .3, 2.4, C.PLANK);
    for (const x of [-5.2, -1.7, 1.7, 5.2]) k.box(x, 2.9, -D / 2 - 2.15, .35, 4.5, .35, C.BARK);
    k.group({ pos: [0, 5.3, -D / 2 - 1.2], rot: [.32, 0, 0] }, () => { k.box(0, 0, 0, W - .4, .2, 3.0, TINT); k.box(0, -.15, -1.45, W - .4, .3, .14, C.TIMBER) });
    const r = gableRoof(b, { w: W, d: D, eave: E, rise: 7.2, rows: 8, seed: 61, ox: .8, oz: .9 });
    for (const s of [-1, 1]) gableEnd(b, s, W / 2 - .2, E, 7.2, D / 2, 0, { fill: C.BARK, window: [1.1, 1.4] });
    stack(b, -W / 2 + .6, 1.8, 1, r.ridge + 1.4, { color: C.STONE, w: 1.6 });
  });

  // =========================================================================
  // Walk-in halls (hollow): walls of thickness t with a door gap, a plank
  // floor (top at `floor`), ceiling ties; colliders are built by the world.
  // =========================================================================
  // Wall with rectangular openings (face-local, u in [-L/2, L/2], height H,
  // thickness t inward from z = 0). openings: [u0, u1, v0, v1].
  const wallWithHoles = (b, f, L, H, t, openings, color) => on(b, f, () => {
    const k = b.kit, cuts = [...openings].sort((a, c) => a[0] - c[0]);
    let u = -L / 2;
    for (const [u0, u1, v0, v1] of cuts) {
      if (u0 > u + .01) k.box((u + u0) / 2, H / 2, t / 2, u0 - u, H, t, color);
      if (v0 > .01) k.box((u0 + u1) / 2, v0 / 2, t / 2, u1 - u0, v0, t, color);
      if (v1 < H - .01) k.box((u0 + u1) / 2, (v1 + H) / 2, t / 2, u1 - u0, H - v1, t, color);
      u = u1;
    }
    if (u < L / 2 - .01) k.box((u + L / 2) / 2, H / 2, t / 2, L / 2 - u, H, t, color);
  });
  // Plank floor with seams and a skirting board along the inner walls.
  const floorAndSkirt = (b, W, D, t, top) => {
    const k = b.kit, iw = W - 2 * t, id = D - 2 * t;
    k.box(0, top / 2, 0, iw, top, id, C.PLANK);
    for (let i = 1; i < 6; i++) k.box(-iw / 2 + i * iw / 6, top + .005, 0, .06, .02, id - .1, C.BARK);
    k.box(0, top + .25, id / 2 - .05, iw, .5, .1, C.TIMBER);
    for (const s of [-1, 1]) k.box(s * (iw / 2 - .05), top + .25, 0, .1, .5, id, C.TIMBER);
  };
  // ShopHall: a tall single-room hall (bank, trade counter, outfitters):
  // stone base course, timber frame, big display windows either side of an
  // arched double door, a shingled gable roof (TINT) with dormers, tie beams.
  const SH = { W: 16, D: 13, t: .8, H: 9.6, floor: .34, door: [-2.2, 2.2, 0, 7.2] };
  building('ShopHall', { tint: '9C3F3A' }, { kind: 'walkin', w: SH.W, d: SH.D, h: SH.H, t: SH.t, floor: SH.floor, opening: { u: 0, w: 4.4, h: 7.2 } }, b => {
    const k = b.kit, { W, D, t, H } = SH, f = faces(W, D);
    floorAndSkirt(b, W, D, t, SH.floor);
    wallWithHoles(b, f.front, W, H, t, [SH.door, [-6.6, -3.4, 2.6, 6.0], [3.4, 6.6, 2.6, 6.0]], C.PLASTER);
    wallWithHoles(b, f.back, W, H, t, [[-5.6, -3.0, 3.0, 6.0], [3.0, 5.6, 3.0, 6.0]], C.PLASTER);
    for (const side of [f.right, f.left]) wallWithHoles(b, side, D - 2 * t, H, t, [[-1.2, 1.2, 3.0, 6.0]], C.PLASTER);
    // Side walls run between the front and back walls: shift them inward is
    // implicit (L = D - 2t centred). Stone base course outside (door gap kept).
    for (const [u0, u1] of [[-W / 2, -2.5], [2.5, W / 2]]) on(b, f.front, () => k.box((u0 + u1) / 2, .6, -.1, u1 - u0, 1.2, .24, C.STONE));
    for (const side of [f.back]) on(b, side, () => k.box(0, .6, -.1, W, 1.2, .24, C.STONE));
    for (const side of [f.right, f.left]) on(b, side, () => k.box(0, .6, -.1, D, 1.2, .24, C.STONE));
    // Timber frame outside.
    for (const x of [-7.85, -6.85, -3.15, 3.15, 6.85, 7.85]) post(b, f.front, x, 1.2, H);
    beam(b, f.front, -8, 8, H - .15); beam(b, f.front, -8, -2.6, 7.6); beam(b, f.front, 2.6, 8, 7.6);
    for (const s of [-1, 1]) cross(b, f.front, s * 6.5, 6.6, s * 3.5, 7.45);
    for (const side of [f.right, f.left]) { for (const x of [-6.35, -1.6, 1.6, 6.35]) post(b, side, x, 1.2, H); beam(b, side, -6.5, 6.5, H - .15); }
    for (const x of [-7.85, -1.5, 1.5, 7.85]) post(b, f.back, x, 1.2, H);
    // Openings dressed: door, windows (glass in the wall's middle plane).
    doorway(b, f.front, 0, 4.4, 7.2, t);
    win(b, f.front, -5, 4.3, 3.2, 3.4, { shutters: C.DEEP, open: t });
    win(b, f.front, 5, 4.3, 3.2, 3.4, { shutters: C.DEEP, open: t });
    for (const x of [-4.3, 4.3]) win(b, f.back, x, 4.5, 2.6, 3.0, { open: t });
    for (const side of [f.right, f.left]) win(b, side, 0, 4.5, 2.4, 3.0, { open: t });
    // Ceiling: tie beams and a ridge purlin seen from inside.
    for (const x of [-4.5, 0, 4.5]) k.box(x, H - .35, 0, .4, .5, D - 2 * t, C.TIMBER);
    const r = gableRoof(b, { w: W, d: D, eave: H, rise: 6.8, rows: 6, seed: 71 });
    k.box(0, r.ridge - .7, 0, W - 2 * t, .4, .4, C.TIMBER);
    for (const s of [-1, 1]) gableEnd(b, s, W / 2, H, 6.8, D / 2, 0, { window: [1.4, 1.6] });
    for (const x of [-4.2, 4.2]) dormer(b, r, x, 2.2, 2.0, 73 + x);
    stack(b, 5.6, 3.2, r.at(3.2) - 1, r.ridge + 1.4);
  });

  // TavernHall: the inn: stone ground storey with a timbered upper storey, a
  // balcony over the door, a hanging sign bracket, a gable chimney stack.
  const TV = { W: 18, D: 13, t: .8, H: 10.4, floor: .34 };
  building('TavernHall', { tint: '7A3E2E' }, { kind: 'walkin', w: TV.W, d: TV.D, h: TV.H, t: TV.t, floor: TV.floor, opening: { u: 0, w: 4.0, h: 7.0 } }, b => {
    const k = b.kit, { W, D, t, H } = TV, f = faces(W, D);
    floorAndSkirt(b, W, D, t, TV.floor);
    const fw = [[-2, 2, 0, 7.0], [-7.6, -4.4, 2.4, 5.2], [4.4, 7.6, 2.4, 5.2], [-6.9, -5.1, 6.8, 9.0], [5.1, 6.9, 6.8, 9.0]];
    wallWithHoles(b, f.front, W, H, t, fw.slice(0, 3), C.STONE);
    wallWithHoles(b, f.back, W, H, t, [[-5, -3, 3.0, 5.4], [3, 5, 3.0, 5.4]], C.STONE);
    for (const side of [f.right, f.left]) wallWithHoles(b, side, D - 2 * t, H, t, [[-3.6, -1.6, 3.0, 5.4]], C.STONE);
    // Upper storey skin: plaster and timber over the stone above y 6.
    for (const side of [f.front, f.back]) on(b, side, () => k.box(0, (6 + H) / 2, -.06, W + .1, H - 6, .1, C.PLASTER));
    for (const side of [f.right, f.left]) on(b, side, () => k.box(0, (6 + H) / 2, -.06, D + .1, H - 6, .1, C.PLASTER));
    for (const x of [-8.9, -7.6, -4.0, 4.0, 7.6, 8.9]) post(b, f.front, x, 6, H);
    beam(b, f.front, -9, 9, 6.1, .32); beam(b, f.front, -9, 9, H - .15);
    for (const x of [-6, 6]) { win(b, f.front, x, 7.9, 1.8, 2.2, { shutters: C.CRIMSON }); }
    for (const side of [f.right, f.left]) { for (const x of [-6.4, 6.4]) post(b, side, x, 6, H); win(b, side, 0, 8.0, 1.6, 2.0, { transom: false }) }
    doorway(b, f.front, 0, 4.0, 7.0, t, { leaf: C.TIMBER });
    for (const x of [-6, 6]) win(b, f.front, x, 3.8, 3.2, 2.8, { sill: C.STONE_LIGHT, box: 83 + x, open: t });
    for (const x of [-4, 4]) win(b, f.back, x, 4.2, 2.0, 2.4, { open: t });
    for (const side of [f.right, f.left]) win(b, side, -2.6, 4.2, 2.0, 2.4, { open: t });
    balcony(b, f.front, 0, 7.5, 6.4, 1.4);
    // Sign bracket and lantern hook beside the door.
    on(b, f.front, () => {
      k.box(3.4, 6.6, -1.0, .16, .16, 2.0, C.IRON);
      k.box(3.4, 6.0, -.55, .1, 1.1, .1, C.IRON, .75);
      k.box(3.4, 5.6, -1.75, .14, 1.4, 1.2, TINT);
      k.box(3.4, 5.6, -1.75, .18, 1.1, .9, C.GOLD);
    });
    for (const x of [-6, 0, 6]) k.box(x, H - .35, 0, .45, .55, D - 2 * t, C.TIMBER);
    const r = gableRoof(b, { w: W, d: D, eave: H, rise: 7.4, rows: 6, seed: 81 });
    for (const s of [-1, 1]) gableEnd(b, s, W / 2, H, 7.4, D / 2, 0, { window: s > 0 ? [1.6, 1.8] : undefined });
    stack(b, -W / 2 - .7, 2.6, 0, r.ridge + 1.2, { color: C.STONE, w: 1.8 });
  });

  // =========================================================================
  // Interiors: furnishing sets for the walk-in halls, authored in the hall's
  // frame (floor top at y = floor). The host is the counter collider.
  // =========================================================================
  const rug = (b, x, z, w, d, color, border = C.GOLD, y = SH.floor) => {
    b.kit.box(x, y + .03, z, w, .06, d, border);
    b.kit.box(x, y + .05, z, w - .5, .06, d - .5, color);
    for (const s of [-1, 1]) b.kit.box(x, y + .06, z + s * (d / 2 - .55), w - 1.1, .06, .14, border);
  };
  const chandelier = (b, x, y, z, r = 1.3) => {
    const k = b.kit;
    k.group({ pos: [x, y, z] }, () => k.ring(r, .1, .12, C.IRON, 10, PI / 2));
    k.box(x, y + 1.2, z, .08, 2.4, .08, C.IRON);
    for (let i = 0; i < 5; i++) { const a = i * 2 * PI / 5; k.jewel(x + Math.cos(a) * r, y + .35, z + Math.sin(a) * r, .07, .16, .07, C.FLAME) }
  };
  const shelfUnit = (b, x, z, w, h, ry, seed, y0 = SH.floor) => b.kit.group({ pos: [x, y0, z], rot: [0, ry, 0] }, () => {
    const k = b.kit;
    k.box(0, h / 2, .25, w, h, .1, C.TIMBER);
    for (const s of [-1, 1]) k.box(s * (w / 2 - .06), h / 2, 0, .12, h, .6, C.TIMBER);
    for (let i = 0; i < 4; i++) {
      const y = .3 + i * (h - .4) / 3;
      k.box(0, y, 0, w - .1, .08, .58, C.PLANK);
      if (i < 3) for (let j = 0; j < 4; j++) {
        const px = -w / 2 + .5 + j * (w - 1) / 3, kind = Math.floor(hash(i, j, seed) * 4);
        if (kind === 0) k.box(px, y + .3, 0, .5, .5, .45, C.PLANK);
        else if (kind === 1) k.group({ pos: [px, y + .04, 0] }, () => k.lathe([[.18, 0], [.2, .3], [.1, .45], [.11, .55]], { n: 6, capStart: true, capEnd: true, color: pick(seed, i * 4 + j, [C.MINT, C.ROSE, C.LAVENDER, C.GLASS]) }));
        else if (kind === 2) for (let q = 0; q < 3; q++) k.box(px - .2 + q * .2, y + .35, 0, .16, .6 - q * .05, .45, pick(seed, q + j, [C.CRIMSON, C.NAVY, C.MOSS, C.BRASS]));
        else k.blob(px, y + .22, 0, .25, .2, .22, { sub: 0, color: pick(seed, j, [C.GOLD, C.STRAW, C.SOIL]) });
      }
    }
  });
  // BankInterior: a panelled teller counter with a brass grille, a vault door
  // set into the back wall, ledgers and coin sacks, a long rug and a chandelier.
  building('BankInterior', { tint: 'C9A24E' }, { kind: 'interior', w: SH.W, d: SH.D, h: SH.H, counter: { c: [0, SH.floor + 1.4, .5], s: [6.5, 2.8, 2] } }, b => {
    const k = b.kit, y0 = SH.floor;
    k.bevelBox(0, y0 + 1.4, .5, 6.5, 2.8, 2, .08, { top: C.MARBLE, side: C.TIMBER, bevel: C.BRASS, bottom: C.TIMBER });
    for (let i = 0; i < 5; i++) k.box(-2.6 + i * 1.3, y0 + 1.3, -.52, .9, 1.8, .06, C.PLANK);
    for (let i = 0; i <= 12; i++) k.box(-3.1 + i * 6.2 / 12, y0 + 3.6, -.25, .06, 1.6, .06, C.BRASS);
    k.box(0, y0 + 4.45, -.25, 6.5, .14, .14, C.BRASS);
    k.box(0, y0 + 2.85, -.3, 6.6, .1, .5, C.BRASS);
    for (const x of [-1.6, 1.6]) k.lathe([[.3, 2.8], [.35, 2.9], [.2, 3.0]].map(([r, y]) => [r, y + y0]), { n: 6, capEnd: true, color: C.BRASS, phase: x });
    // Vault door on the back wall.
    k.group({ pos: [0, y0 + 3.2, SH.D / 2 - SH.t - .02], rot: [-PI / 2, 0, 0] }, () => {
      k.lathe([[2.2, 0], [2.2, .12], [1.9, .25], [0, .3]], { n: 16, capStart: true, color: C.IRON });
      k.ring(1.5, .16, .2, C.BRASS, 16, PI / 2, 0, PI * 2, .32);
    });
    for (let i = 0; i < 6; i++) { const a = i * PI / 3; k.box(Math.cos(a) * .7, y0 + 3.2 + Math.sin(a) * .7, SH.D / 2 - SH.t - .5, .12, .9, .12, C.BRASS, a) }
    for (const s of [-1, 1]) shelfUnit(b, s * 5.3, SH.D / 2 - SH.t - .5, 3.6, 3.6, 0, 91 + s);
    for (const s of [-1, 1]) {
      k.bevelBox(s * 5.6, y0 + .45, 1.8, 1.6, .9, 1.0, .06, { top: C.BRASS, side: C.TIMBER, bevel: C.BRASS, bottom: C.TIMBER });
      for (let q = 0; q < 3; q++) k.blob(s * (5.0 + q * .5), y0 + .35, -2.5 - q * .3, .32, .3, .3, { sub: 0, color: C.STRAW });
    }
    rug(b, 0, -3.1, 3.2, 4.6, C.CRIMSON);
    chandelier(b, 0, 7.6, -1.5, 1.4);
  });
  // ShopInterior: a shop counter with scales, shelving on the back and side
  // walls stocked with jars, bolts of cloth and goods, crates and barrels.
  building('ShopInterior', { tint: '9DF3D7' }, { kind: 'interior', w: SH.W, d: SH.D, h: SH.H, counter: { c: [0, SH.floor + 1.4, .5], s: [6.5, 2.8, 2] } }, b => {
    const k = b.kit, y0 = SH.floor;
    k.bevelBox(0, y0 + 1.4, .5, 6.5, 2.8, 2, .08, { top: C.PLANK, side: C.TIMBER, bevel: C.BARK, bottom: C.TIMBER });
    for (let i = 0; i < 4; i++) k.box(-2.4 + i * 1.6, y0 + 1.3, -.52, 1.2, 1.9, .06, TINT_DARK);
    // Scales and goods on the counter.
    k.box(-1.6, y0 + 3.3, .5, .1, 1.0, .1, C.BRASS);
    k.box(-1.6, y0 + 3.8, .5, 1.3, .07, .07, C.BRASS);
    for (const s of [-1, 1]) k.group({ pos: [-1.6 + s * .6, y0 + 3.3, .5] }, () => k.lathe([[0, 0], [.3, .08], [.32, .14]], { n: 8, color: C.BRASS }));
    for (let i = 0; i < 3; i++) k.jewel(1.0 + i * .7, y0 + 3.05, .4, .2, .2, .2, pick(101, i, [C.ROSE, C.FLAME, C.MINT]));
    shelfUnit(b, -3.6, SH.D / 2 - SH.t - .4, 4.2, 4.2, 0, 102);
    shelfUnit(b, 3.6, SH.D / 2 - SH.t - .4, 4.2, 4.2, 0, 103);
    shelfUnit(b, SH.W / 2 - SH.t - .4, -2.4, 3.6, 3.6, -PI / 2, 104);
    for (let i = 0; i < 3; i++) k.bevelBox(-5.6 + i * .2, y0 + .45 + i * .9, 3.6 - i * .1, 1.1 - i * .15, .9, 1.1 - i * .15, .05, C.PLANK);
    for (const x of [5.4, 6.3]) k.group({ pos: [x, y0, 3.4] }, () => k.lathe([[.4, 0], [.48, .45], [.48, .9], [.4, 1.3]], { n: 8, capStart: true, capEnd: true, capColor: C.PLANK, color: (l, i) => i % 2 ? C.BARK : C.PLANK }));
    rug(b, 0, -3.4, 3.0, 4.2, TINT_DARK, C.STRAW);
    chandelier(b, 0, 7.4, -1.2, 1.1);
  });
  // TavernInterior: a long bar along the right wall with casks behind it, a
  // stone hearth with a fire on the left wall, tables and stools, a rug.
  building('TavernInterior', { tint: 'C15557' }, { kind: 'interior', w: TV.W, d: TV.D, h: TV.H, counter: { c: [5.6, TV.floor + 1.3, 1.0], s: [2, 2.6, 8] } }, b => {
    const k = b.kit, y0 = TV.floor;
    k.bevelBox(5.6, y0 + 1.3, 1.0, 2, 2.6, 8, .08, { top: C.PLANK, side: C.TIMBER, bevel: C.BRASS, bottom: C.TIMBER });
    for (let i = 0; i < 5; i++) k.box(4.58, y0 + 1.2, -2.2 + i * 1.6, .06, 1.8, 1.1, C.PLANK);
    for (let i = 0; i < 3; i++) for (let j = 0; j < 2; j++) k.group({ pos: [7.45, y0 + .7 + j * 1.5, -1.6 + i * 2.2], rot: [0, 0, PI / 2] }, () => k.lathe([[.55, -.6], [.68, 0], [.55, .6]], { n: 8, capStart: true, capEnd: true, capColor: C.PLANK, color: (l, q) => q % 2 ? C.BARK : C.PLANK }));
    for (let i = 0; i < 4; i++) k.group({ pos: [5.4, y0 + 2.62, -1.6 + i * 1.5] }, () => k.lathe([[.12, 0], [.14, .35], [.11, .38]], { n: 5, capStart: true, color: C.BRASS }));
    // Hearth on the left wall.
    const hx = -TV.W / 2 + TV.t + .6;
    k.bevelBox(hx, y0 + 2.6, 0, 1.2, 5.2, 4.2, .1, { top: C.STONE_LIGHT, side: C.STONE, bevel: C.STONE_LIGHT, bottom: C.STONE_DARK });
    k.box(hx + .62, y0 + 1.2, 0, .1, 2.0, 2.4, C.INK);
    k.box(hx + .7, y0 + 2.4, 0, .5, .3, 3.4, C.STONE_LIGHT);
    for (let i = 0; i < 5; i++) k.jewel(hx + .85, y0 + .5 + (i % 2) * .2, -.8 + i * .4, .16, .4 + (i % 3) * .15, .14, i % 2 ? C.FLAME : C.EMBER);
    for (let i = 0; i < 3; i++) k.box(hx + .9, y0 + .2, -.6 + i * .6, .25, .25, 1.0, C.BARK, i * .3);
    // Tables with stools.
    for (const [tx, tz] of [[-3.5, -2.5], [-3.5, 2.8], [1.2, 0.2]]) {
      k.group({ pos: [tx, y0, tz] }, () => {
        k.lathe([[1.1, 2.3], [1.1, 2.45]], { n: 10, capStart: true, capEnd: true, color: C.PLANK });
        k.lathe([[.12, 0], [.12, 2.3]], { n: 6, color: C.TIMBER });
        k.lathe([[.5, 0], [.15, .12]], { n: 6, capStart: true, color: C.TIMBER });
        for (let q = 0; q < 3; q++) { const a = q * 2 * PI / 3 + tx; k.group({ pos: [Math.cos(a) * 1.7, 0, Math.sin(a) * 1.7] }, () => k.lathe([[.38, 1.35], [.38, 1.5]], { n: 8, capStart: true, capEnd: true, color: C.PLANK })); k.box(Math.cos(a) * 1.7, .68, Math.sin(a) * 1.7, .14, 1.36, .14, C.TIMBER) }
        k.jewel(.3, 2.58, .1, .16, .2, .16, C.BRASS);
      });
    }
    rug(b, -1.5, 0, 6.0, 7.5, C.CRIMSON, C.GOLD, y0);
    for (const x of [-3, 3]) chandelier(b, x, 8.2, 0, 1.2);
  });
  // HallFurnishings: a long rug runner, two benches either side of a trestle
  // table with candles, and an iron chandelier (guild and council halls; the
  // host is an invisible box: nothing here blocks).
  building('HallFurnishings', { tint: '3F6FB5' }, { kind: 'interior', w: 8, d: 18, h: 7 }, b => {
    const k = b.kit;
    k.box(0, .03, 0, 4.4, .06, 18, C.GOLD);
    k.box(0, .05, 0, 3.8, .06, 17.4, TINT);
    for (let i = 0; i < 6; i++) k.jewel(0, .09, -7.5 + i * 3, .6, .02, .6, TINT_LIGHT);
    for (const z of [-4.5, 4.5]) {
      k.bevelBox(2.9, 2.3, z, 2.0, .2, 6.0, .05, C.PLANK);
      for (const zz of [-2.5, 2.5]) { k.box(2.9, 1.1, z + zz, 1.6, 2.2, .2, C.TIMBER); k.box(2.9, .2, z + zz, 1.8, .2, .5, C.TIMBER) }
      for (const s of [-1, 1]) { k.box(2.9 + s * 1.7, 1.2, z, .7, .16, 5.6, C.PLANK); for (const zz of [-2.4, 2.4]) k.box(2.9 + s * 1.7, .6, z + zz, .5, 1.2, .16, C.TIMBER) }
      for (let q = 0; q < 3; q++) { k.box(2.9, 2.6, z - 2 + q * 2, .14, .4, .14, C.CLOTH); k.jewel(2.9, 2.9, z - 2 + q * 2, .05, .12, .05, C.FLAME) }
    }
    k.box(-3.2, .6, 0, .7, .16, 12, C.PLANK);
    for (const zz of [-5.5, 0, 5.5]) k.box(-3.2, .3, zz, .5, .6, .16, C.TIMBER);
    k.group({ pos: [0, 6.2, 0] }, () => k.ring(1.6, .12, .14, C.IRON, 12, PI / 2));
    k.box(0, 6.6, 0, .1, .8, .1, C.IRON);
    for (let i = 0; i < 6; i++) { const a = i * PI / 3; k.jewel(Math.cos(a) * 1.6, 6.45, Math.sin(a) * 1.6, .08, .2, .08, C.FLAME) }
  });
  return KIT;
};
