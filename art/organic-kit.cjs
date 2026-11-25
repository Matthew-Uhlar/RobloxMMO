// Organic re-authoring kit (docs/DEPTH-CONTRACT.md §55): shared, deterministic
// helpers for the smooth world / creature / outfit shapes. Loaded by
// art/generate-props.cjs (the kit primitives fair their profiles with `fair`)
// and by the shape files (profiles, sections, noise).
//
// Everything here is pure geometry on plain arrays: no randomness (hash-based
// value noise), no kit calls.
'use strict';
const PI = Math.PI;
const hash = (a, b, seed) => {
  let h = Math.imul(a + 1, 0x9E3779B1) ^ Math.imul(b + 7, 0x85EBCA6B) ^ Math.imul(seed + 13, 0xC2B2AE35);
  h = Math.imul(h ^ (h >>> 15), 0x2C1B3C6D); h = Math.imul(h ^ (h >>> 12), 0x297A2D39); h ^= h >>> 15;
  return (h >>> 0) / 4294967296;
};
// Continuous 3D value noise and fbm (smooth, [-1, 1]).
const sm = t => t * t * (3 - 2 * t);
const noise3 = (x, y, z, s) => {
  const ix = Math.floor(x), iy = Math.floor(y), iz = Math.floor(z);
  const fx = sm(x - ix), fy = sm(y - iy), fz = sm(z - iz);
  const l = (a, b, c) => hash(ix + a + 4099 * (iy + b), iz + c, s);
  const lerp = (a, b, t) => a + (b - a) * t;
  return lerp(lerp(lerp(l(0, 0, 0), l(1, 0, 0), fx), lerp(l(0, 1, 0), l(1, 1, 0), fx), fy),
    lerp(lerp(l(0, 0, 1), l(1, 0, 1), fx), lerp(l(0, 1, 1), l(1, 1, 1), fx), fy), fz) * 2 - 1;
};
// Multi-octave fbm of a point (frequency f, octaves oct; lacunarity 2, gain .5).
const fbm = (p, f, s, oct = 3) => {
  let a = 0, w = 1, t = 0;
  for (let k = 0; k < oct; k++) { a += w * noise3(p[0] * f + 17 * k, p[1] * f - 5 * k, p[2] * f + 3 * k, s + k); t += w; w *= .5; f *= 2; }
  return a / t;
};
const sstep = (e0, e1, x) => sm(Math.min(1, Math.max(0, (x - e0) / (e1 - e0))));
const clamp = (x, a, b) => Math.min(b, Math.max(a, x));

// Centripetal Catmull-Rom fairing of a polyline of N-dimensional points:
// each span is split so the direction turns at most `maxTurn` radians per
// sample (and spans stay at most `maxLen` long when given). Returns the new
// points and, per point, its fractional source index (so per-level callbacks
// keep their meaning). `dims` limits the turn measure to the first k
// coordinates (the radius of a tube still bends the surface, so tubes pass 4).
function fair(points, maxTurn = 14 * PI / 180, { maxLen = Infinity, dims, closedEnds = true } = {}) {
  const n = points.length;
  if (n < 3 && maxLen === Infinity) return { points: points.map(p => p.slice()), src: points.map((_, i) => i) };
  const k = dims || points[0].length;
  const sub = (a, b) => a.slice(0, k).map((x, q) => x - b[q]);
  const len = a => Math.hypot(...a);
  const turnAt = i => {
    if (i <= 0 || i >= n - 1) return 0;
    const u = sub(points[i], points[i - 1]), w = sub(points[i + 1], points[i]), lu = len(u), lw = len(w);
    if (lu < 1e-9 || lw < 1e-9) return 0;
    return Math.acos(clamp(u.reduce((t, x, q) => t + x * w[q], 0) / lu / lw, -1, 1));
  };
  const out = [points[0].slice()], src = [0];
  for (let i = 0; i < n - 1; i++) {
    const p0 = points[Math.max(0, i - 1)], p1 = points[i], p2 = points[i + 1], p3 = points[Math.min(n - 1, i + 2)];
    const segLen = len(sub(p2, p1));
    const steps = Math.max(1, Math.min(10, Math.ceil(1.0 * Math.max(turnAt(i), turnAt(i + 1)) / maxTurn)), Math.ceil(segLen / maxLen));
    // Centripetal parameterisation (alpha .5): no cusps or self-loops.
    const d01 = Math.max(1e-6, Math.sqrt(len(sub(p1, p0)) || segLen)), d12 = Math.max(1e-6, Math.sqrt(segLen)), d23 = Math.max(1e-6, Math.sqrt(len(sub(p3, p2)) || segLen));
    const t0 = 0, t1 = d01, t2 = t1 + d12, t3 = t2 + d23;
    const dim = p1.length;
    for (let s = 1; s <= steps; s++) {
      const t = t1 + (t2 - t1) * s / steps, pt = [];
      for (let q = 0; q < dim; q++) {
        const P0 = i === 0 ? 2 * p1[q] - p2[q] : p0[q], P3 = i + 2 > n - 1 ? 2 * p2[q] - p1[q] : p3[q];
        const A1 = (t1 - t) / (t1 - t0) * P0 + (t - t0) / (t1 - t0) * p1[q];
        const A2 = (t2 - t) / (t2 - t1) * p1[q] + (t - t1) / (t2 - t1) * p2[q];
        const A3 = (t3 - t) / (t3 - t2) * p2[q] + (t - t2) / (t3 - t2) * P3;
        const B1 = (t2 - t) / (t2 - t0) * A1 + (t - t0) / (t2 - t0) * A2;
        const B2 = (t3 - t) / (t3 - t1) * A2 + (t - t1) / (t3 - t1) * A3;
        pt.push((t2 - t) / (t2 - t1) * B1 + (t - t1) / (t2 - t1) * B2);
      }
      // A lathe pole (radius 0) stays exactly on the axis.
      if (s === steps) for (let q = 0; q < dim; q++) pt[q] = p2[q];
      out.push(pt); src.push(i + s / steps);
    }
  }
  return { points: out, src };
}

// ---------------------------------------------------------------------------
// Profiles ([radius, y] bottom to top) for lathes.
// ---------------------------------------------------------------------------
// A rounded closure: from radius r at height y up to a pole h higher, the
// normal turning evenly (quarter ellipse sampled by normal angle).
const dome = (r, y, h, steps = 5) => Array.from({ length: steps }, (_, k) => {
  const f = (k + 1) / steps * PI / 2, a = Math.atan2(h * Math.sin(f), r * Math.cos(f));
  return [k === steps - 1 ? 0 : r * Math.cos(a), y + h * Math.sin(a)];
});
// The same closure downward (a rounded underside to a pole below).
const bowl = (r, y, h, steps = 5) => dome(r, -y, h, steps).map(([x, z]) => [x, -z]).reverse();
// A rounded cap (mushroom caps, petal cups, brims): a flat underside from r0
// out to the rim, a rounded rim (arc of radius th, <= arcDeg per level) and a
// parabolic dome of height `rise` meeting the rim tangentially, to a pole.
const capProfile = (r0, R, y, th, rise, domeSteps = 6, arcDeg = 18) => {
  const x0 = R - th, phi = Math.atan2(2 * rise, x0), pts = [[r0, y], [x0, y]];
  const a0 = -PI / 2, a1 = PI / 2 - phi, steps = Math.max(3, Math.ceil((a1 - a0) / (arcDeg * PI / 180)));
  for (let k = 1; k <= steps; k++) { const a = a0 + (a1 - a0) * k / steps; pts.push([x0 + th * Math.cos(a), y + th + th * Math.sin(a)]); }
  const [xe, ye] = pts[pts.length - 1], h = xe * Math.tan(phi) / 2;
  for (let k = 1; k <= domeSteps; k++) { const x = xe * (1 - k / domeSteps); pts.push([k === domeSteps ? 0 : x, ye + h * (1 - (x / xe) ** 2)]); }
  return pts;
};
// A rounded rim arc: from angle a0 to a1 (radians, 0 = outward, PI/2 = up)
// about the centre [cx, cy] with radius th, at most arcDeg per level.
const arc = (cx, cy, th, a0, a1, arcDeg = 18) => {
  const steps = Math.max(2, Math.ceil(Math.abs(a1 - a0) / (arcDeg * PI / 180)));
  return Array.from({ length: steps + 1 }, (_, k) => { const a = a0 + (a1 - a0) * k / steps; return [cx + th * Math.cos(a), cy + th * Math.sin(a)]; });
};
// A spindle / gem profile: pole at y0, widest r at yMid, pole at y1, rounded
// through `steps` levels each side (sine bulge, no hard equator).
const spindleProfile = (r, y0, yMid, y1, steps = 6, power = 1) => {
  const pts = [[0, y0]];
  for (let k = 1; k < steps; k++) { const t = k / steps; pts.push([r * Math.sin(t * PI / 2) ** power, y0 + (yMid - y0) * (1 - Math.cos(t * PI / 2))]); }
  pts.push([r, yMid]);
  for (let k = 1; k < steps; k++) { const t = k / steps; pts.push([r * Math.cos(t * PI / 2) ** power, yMid + (y1 - yMid) * Math.sin(t * PI / 2)]); }
  pts.push([0, y1]);
  return pts;
};
// Quadratic Bezier resampled into k points (branches, roots, horns).
const curve = (a, b, c, k = 5) => Array.from({ length: k }, (_, i) => { const t = i / (k - 1), u = 1 - t; return [0, 1, 2].map(q => u * u * a[q] + 2 * u * t * b[q] + t * t * c[q]); });
// Cubic Bezier resampled into k points.
const cubic = (a, b, c, d, k = 6) => Array.from({ length: k }, (_, i) => { const t = i / (k - 1), u = 1 - t; return [0, 1, 2].map(q => u * u * u * a[q] + 3 * u * u * t * b[q] + 3 * u * t * t * c[q] + t * t * t * d[q]); });

// ---------------------------------------------------------------------------
// Closed cross-sections for lofts, sampled by normal angle so the normal turns
// evenly (2pi/m per point) around even the thinnest lens: flat wings, blades,
// cloth and brims never fold at their edges.
// ---------------------------------------------------------------------------
// Superellipse |x/a|^p + |y/b|^p = 1 (p = 2 ellipse, larger = boxier).
function section(a, b, m = 20, p = 2, phase = 0, cx = 0, cy = 0) {
  const q = p / (p - 1);
  return Array.from({ length: m }, (_, k) => {
    const f = phase + k * 2 * PI / m, c = Math.cos(f), s = Math.sin(f);
    const lam = ((a * Math.abs(c)) ** q + (b * Math.abs(s)) ** q) ** (-1 / q);
    const u = Math.sign(c) * (lam * a * Math.abs(c)) ** (1 / (p - 1)), v = Math.sign(s) * (lam * b * Math.abs(s)) ** (1 / (p - 1));
    return [cx + u * a, cy + v * b];
  });
}
// A thin section bent along a circular arc of radius R (cloth wrapped around
// a body): the chord (x) follows the arc, the thickness (y) stays normal to it.
function bentSection(a, b, R, m = 20, p = 2) {
  return section(a, b, m, p).map(([x, y]) => {
    if (!isFinite(R) || Math.abs(R) > 1e6) return [x, y];
    const t = x / R; return [Math.sin(t) * (R - y), R - Math.cos(t) * (R - y)];
  });
}
module.exports = { PI, hash, noise3, fbm, sstep, clamp, fair, dome, bowl, capProfile, arc, spindleProfile, curve, cubic, section, bentSection };
// Parameters of a symmetric quadratic Bezier corner (turning by phi) at which
// its tangent has turned evenly: k = 0..steps.
module.exports.cornerT = (k, steps, phi = PI / 2) => { const th = phi * k / steps; const a = Math.sin(th), b = Math.sin(phi - th); return a + b > 1e-12 ? a / (a + b) : k / steps; };
// A filleted, graded polyline (lathe profiles, tube paths in 2D): every corner
// of `points` is rounded by an arc of radius `rc` (a number, or one per
// corner; clamped to 45 % of the shorter neighbour), sampled at <= stepDeg per
// level; straight runs are split so their pieces grow by at most `grow` from
// the neighbouring arc steps (no long band beside a short one) up to maxLen.
// A pole ([0, y]) at either end stays exact; its neighbour segment should
// approach the axis level for a smooth closure.
function rounded(points, rc = .1, { stepDeg = 12, grow = Infinity, maxLen = Infinity, minSeg = .005 } = {}) {
  const n = points.length, R = i => Array.isArray(rc) ? (rc[i] ?? 0) : rc;
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1]], len = a => Math.hypot(a[0], a[1]);
  // Corner arcs: [start point, ...arc points, end point] per interior corner.
  const arcs = [];
  for (let i = 1; i < n - 1; i++) {
    const u = sub(points[i], points[i - 1]), w = sub(points[i + 1], points[i]), lu = len(u), lw = len(w);
    const du = [u[0] / lu, u[1] / lu], dw = [w[0] / lw, w[1] / lw];
    const cross = du[0] * dw[1] - du[1] * dw[0], dot = du[0] * dw[0] + du[1] * dw[1];
    const phi = Math.atan2(Math.abs(cross), dot);
    if (phi < 1e-3 || R(i) <= 0) { arcs[i] = [points[i]]; continue; }
    let d = R(i) * Math.tan(phi / 2);
    d = Math.min(d, .45 * lu, .45 * lw);
    // Steps: <= stepDeg each, but no arc piece shorter than minSeg (mm-packed geometry).
    const r = d / Math.tan(phi / 2), steps = Math.max(1, Math.min(Math.ceil(phi * 180 / Math.PI / stepDeg), Math.floor(r * phi / minSeg)));
    if (r * phi < 2 * minSeg) { arcs[i] = [points[i]]; continue; }
    const a = [points[i][0] - du[0] * d, points[i][1] - du[1] * d];
    const nrm = cross > 0 ? [-du[1], du[0]] : [du[1], -du[0]];
    const c = [a[0] + nrm[0] * r, a[1] + nrm[1] * r];
    const a0 = Math.atan2(a[1] - c[1], a[0] - c[0]), sgn = cross > 0 ? 1 : -1, pts = [];
    for (let k = 0; k <= steps; k++) { const t = a0 + sgn * phi * k / steps; pts.push([c[0] + r * Math.cos(t), c[1] + r * Math.sin(t)]); }
    arcs[i] = pts;
  }
  const out = [points[0]];
  const run = (from, to, h0, h1) => {
    // Pieces from `from` to `to`, growing from h0 (start) and h1 (end) by `grow`.
    const L = len(sub(to, from)), cuts = [];
    if (L < 1e-9) return;
    let s0 = 0, s1 = L, a = Math.max(h0, 1e-4), b = Math.max(h1, 1e-4), left = [], right = [];
    while (s1 - s0 > Math.min(maxLen, Math.max(a, b) * grow) * 1.0001) {
      if (a <= b) { a = Math.min(a * grow, maxLen); if (s0 + a >= s1) break; s0 += a; left.push(s0); }
      else { b = Math.min(b * grow, maxLen); if (s1 - b <= s0) break; s1 -= b; right.unshift(s1); }
    }
    cuts.push(...left, ...right);
    const dir = [(to[0] - from[0]) / L, (to[1] - from[1]) / L];
    for (const s of cuts) out.push([from[0] + dir[0] * s, from[1] + dir[1] * s]);
    out.push(to);
  };
  const step = pts => pts.length > 1 ? len(sub(pts[1], pts[0])) : Infinity;
  let prev = points[0], hPrev = Infinity;
  for (let i = 1; i < n; i++) {
    const arcPts = i < n - 1 ? arcs[i] : [points[n - 1]];
    const h = arcPts.length > 1 ? step(arcPts) : Infinity;
    const h0 = isFinite(hPrev) ? hPrev : (isFinite(h) ? h : maxLen), h1 = isFinite(h) ? h : h0;
    run(prev, arcPts[0], Math.min(h0, maxLen), Math.min(h1, maxLen));
    for (let k = 1; k < arcPts.length; k++) out.push(arcPts[k]);
    prev = arcPts[arcPts.length - 1];
    hPrev = arcPts.length > 1 ? step(arcPts.slice(-2)) : hPrev;
  }
  return out.map(([x, y]) => [Math.abs(x) < 1e-9 ? 0 : x, y]).filter((p, i, a) => i === 0 || Math.hypot(p[0] - a[i - 1][0], p[1] - a[i - 1][1]) > 1e-4);
}
module.exports.rounded = rounded;
// A rounded rectangle section (2hw x 2hh, corner radius rc), counter-clockwise
// from the right side's middle: each corner is a quarter arc of kArc steps,
// the flat sides are split into kW (top / bottom) and kH (left / right)
// pieces. With rc = hh it is a stadium (thin cloth, brims, blades whose broad
// faces must still bend with a wrap or fold).
function roundRect(hw, hh, rc, { kArc = 4, kW = 4, kH = 1, cx = 0, cy = 0 } = {}) {
  rc = Math.min(rc, hw, hh);
  const pts = [], fx = hw - rc, fy = hh - rc;
  const corner = (ox, oy, a0) => { for (let k = 0; k < kArc; k++) { const a = a0 + (PI / 2) * k / kArc; pts.push([cx + ox + rc * Math.cos(a), cy + oy + rc * Math.sin(a)]); } };
  const side = (x0, y0, x1, y1, k) => { for (let j = 0; j < k; j++) { const t = j / k; pts.push([cx + x0 + (x1 - x0) * t, cy + y0 + (y1 - y0) * t]); } };
  // right side (bottom half -> top half), corners, sides; skip zero-length sides.
  if (fy > 1e-9) side(hw, 0, hw, fy, Math.max(1, Math.ceil(kH / 2)));
  corner(fx, fy, 0);
  if (fx > 1e-9) side(fx, hh, -fx, hh, kW);
  corner(-fx, fy, PI / 2);
  if (fy > 1e-9) side(-hw, fy, -hw, -fy, kH);
  corner(-fx, -fy, PI);
  if (fx > 1e-9) side(-fx, -hh, fx, -hh, kW);
  corner(fx, -fy, 3 * PI / 2);
  if (fy > 1e-9) side(hw, -fy, hw, 0, Math.max(1, Math.floor(kH / 2)));
  return pts;
}
module.exports.roundRect = roundRect;
// A whole ellipsoid profile (radius r, from y - hb to y + ht): rounded bottom
// pole, equator, rounded top pole; the normal turns evenly (steps per half).
module.exports.ellipsoid = (r, y = 0, hb = r, ht = r, steps = 5) => [...bowl(r, y, hb, steps), [r, y], ...dome(r, y, ht, steps)];
