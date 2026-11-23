"""Headless town renderer (World Art pass 2, docs/DEPTH-CONTRACT.md §40).

Renders a scene exported by tools/dump-scene.luau: the island's building meshes
(the art/*.obj masters placed exactly as the forge places them: ShapeBox =
fit box, 1:1), every other visible part as a box / cylinder / ball, and, at
night, the lit window panes (emissive, with a soft bloom). Flat Lambert light,
z-buffered (art/render-icons.py rasteriser). No Roblox materials, textures,
shadows or Future lighting: judge those in Studio.

    lune run tools/dump-scene.luau "Compass Quay" /tmp/quay.json
    python3 tools/render-town.py /tmp/quay.json docs/screenshots/town-day.png \
        --eye 95,70,95 --at 20,0,-5 --fov 50 [--night] [--size 1600x900]
"""
import importlib.util
import json
import math
import os
import sys

import numpy
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("render_icons", os.path.join(ROOT, "art", "render-icons.py"))
icons = importlib.util.module_from_spec(spec)
spec.loader.exec_module(icons)


def hex_rgb(h):
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def transform(cf):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf
    rot = numpy.array([[r00, r01, r02], [r10, r11, r12], [r20, r21, r22]])
    return numpy.array([x, y, z]), rot


BOX_FACES = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (3, 7, 6, 2), (0, 4, 7, 3), (1, 2, 6, 5)]


def box_tris(size):
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    corners = [(sx * hx, sy * hy, sz * hz) for sx, sy, sz in [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]]
    tris = []
    for a, b, c, d in BOX_FACES:
        tris.append((corners[a], corners[b], corners[c]))
        tris.append((corners[a], corners[c], corners[d]))
    return tris


def cylinder_tris(size, n=14):
    # Roblox cylinders run along local X; Size.Y / Size.Z are the diameter.
    h, ry, rz = size[0] / 2, size[1] / 2, size[2] / 2
    ring = [(math.cos(i * 2 * math.pi / n) * ry, math.sin(i * 2 * math.pi / n) * rz) for i in range(n)]
    tris = []
    for i in range(n):
        (y0, z0), (y1, z1) = ring[i], ring[(i + 1) % n]
        tris.append(((-h, y0, z0), (h, y0, z0), (h, y1, z1)))
        tris.append(((-h, y0, z0), (h, y1, z1), (-h, y1, z1)))
        tris.append(((h, 0, 0), (h, y1, z1), (h, y0, z0)))
        tris.append(((-h, 0, 0), (-h, y0, z0), (-h, y1, z1)))
    return tris


def ball_tris(size, n=10):
    r = numpy.array(size) / 2
    tris = []
    for i in range(n):
        t0, t1 = math.pi * i / n, math.pi * (i + 1) / n
        for j in range(2 * n):
            p0, p1 = 2 * math.pi * j / (2 * n), 2 * math.pi * (j + 1) / (2 * n)
            def pt(t, p):
                return (math.sin(t) * math.cos(p) * r[0], math.cos(t) * r[1], math.sin(t) * math.sin(p) * r[2])
            tris.append((pt(t0, p0), pt(t1, p0), pt(t1, p1)))
            tris.append((pt(t0, p0), pt(t1, p1), pt(t0, p1)))
    return tris


def main():
    args = sys.argv[1:]
    scene_path, out_path = args[0], args[1]
    opts = {"eye": "95,70,95", "at": "20,0,-5", "fov": "50", "size": "1600x900"}
    night = "--night" in args
    for i, a in enumerate(args):
        if a.startswith("--") and a[2:] in opts:
            opts[a[2:]] = args[i + 1]
    eye = numpy.array([float(v) for v in opts["eye"].split(",")])
    target = numpy.array([float(v) for v in opts["at"].split(",")])
    width, height = (int(v) for v in opts["size"].split("x"))
    sup = 2
    W, H = width * sup, height * sup
    forward = target - eye
    forward /= numpy.linalg.norm(forward)
    right = numpy.cross(forward, [0, 1, 0])
    right /= numpy.linalg.norm(right)
    up = numpy.cross(right, forward)
    focal = 1 / math.tan(math.radians(float(opts["fov"])) / 2)
    sky_top, sky_bottom = ((0.11, 0.14, 0.27), (0.25, 0.22, 0.36)) if night else ((0.47, 0.71, 0.93), (0.80, 0.90, 0.97))
    pixels = numpy.zeros((H, W, 3), dtype=numpy.uint8)
    for row in range(H):
        t = row / H
        pixels[row, :] = [int(255 * (sky_top[k] * (1 - t) + sky_bottom[k] * t)) for k in range(3)]
    zbuffer = numpy.full((H, W), numpy.inf)
    emissive = numpy.zeros((H, W), dtype=bool)
    sun = numpy.array([0.45, 0.8, 0.4]) if not night else numpy.array([-0.3, 0.7, 0.6])
    sun /= numpy.linalg.norm(sun)
    ambient, diffuse = (0.55, 0.55) if not night else (0.28, 0.22)
    tint_night = numpy.array([0.75, 0.82, 1.15]) if night else numpy.array([1, 1, 1])

    def project(p):
        rel = p - eye
        depth = rel @ forward
        if depth < 0.499:
            return None
        # Vertical field of view: both axes scale by H / 2.
        # -1/depth interpolates perspective-correctly in screen space (huge ground
        # triangles would otherwise win the z-test against nearby floors).
        return (W / 2 + (rel @ right) / depth * focal * H / 2, H / 2 - (rel @ up) / depth * focal * H / 2, -1 / depth)

    def draw(tri, colour, glow=False):
        a, b, c = tri
        n = numpy.cross(b - a, c - a)
        length = numpy.linalg.norm(n)
        if length < 1e-9:
            return
        n /= length
        mid = (a + b + c) / 3
        if n @ (eye - mid) < 0:
            n = -n
        # Clip against the near plane (a camera inside a hall sees big floor
        # triangles that reach behind it), then fan the polygon.
        near = 0.5
        poly, depths = [a, b, c], [(p - eye) @ forward for p in (a, b, c)]
        clipped = []
        for i in range(3):
            p, q, dp, dq = poly[i], poly[(i + 1) % 3], depths[i], depths[(i + 1) % 3]
            if dp >= near:
                clipped.append(p)
            if (dp >= near) != (dq >= near):
                clipped.append(p + (q - p) * ((near - dp) / (dq - dp)))
        if len(clipped) < 3:
            return
        projected = [project(p) for p in clipped]
        if any(p is None for p in projected):
            return
        if glow:
            shaded = numpy.array(colour) * 255
        else:
            shade = ambient + diffuse * max(0.0, float(n @ sun))
            shaded = numpy.clip(numpy.array(colour) * 255 * shade * tint_night, 0, 255)
        before = zbuffer.copy() if glow else None
        for i in range(1, len(projected) - 1):
            icons.rasterise(pixels, zbuffer, [projected[0], projected[i], projected[i + 1]], [tuple(shaded)] * 3)
        if glow:
            emissive[zbuffer < before] = True

    with open(scene_path) as handle:
        scene = json.load(handle)
    palette = icons.read_palette()
    cache = {}
    for m in scene["meshes"]:
        name = m["shape"]
        if name not in cache:
            vertices, faces, meta = icons.read_obj(name)
            v = numpy.array(vertices)
            lo, hi = v.min(axis=0), v.max(axis=0)
            cache[name] = (v, faces, meta, (lo + hi) / 2, hi - lo)
        v, faces, meta, centre, extent = cache[name]
        pos, rot = transform(m["cf"])
        k = numpy.array(m["box"]) / extent
        world = (rot @ ((v - centre) * k).T).T + pos
        tint = hex_rgb(m["tint"]) if m.get("tint") else (hex_rgb(meta["tint"]) if meta["tint"] else None)
        shades = icons.tint_shades(tint) if tint else {}
        for ids, material in faces:
            colour = shades.get(material) or palette[material]
            draw((world[ids[0]], world[ids[1]], world[ids[2]]), colour)
    for part in scene["boxes"]:
        pos, rot = transform(part["cf"])
        size = part["size"]
        tris = cylinder_tris(size) if part["kind"] == "cylinder" else ball_tris(size) if part["kind"] == "ball" else box_tris(size)
        colour = hex_rgb(part["color"])
        for tri in tris:
            draw(tuple((rot @ numpy.array(p)) + pos for p in tri), colour)
    if night:
        for pane in scene["panes"]:
            pos, rot = transform(pane["cf"])
            for tri in box_tris(pane["size"]):
                draw(tuple((rot @ numpy.array(p)) + pos for p in tri), (1.0, 0.80, 0.48), glow=True)
    image = Image.fromarray(pixels)
    if night:
        mask = Image.fromarray((emissive * 255).astype(numpy.uint8)).filter(ImageFilter.GaussianBlur(10 * sup))
        glow = numpy.array(mask, dtype=numpy.float32)[..., None] / 255 * numpy.array([255, 190, 110]) * 0.55
        image = Image.fromarray(numpy.clip(numpy.array(image, dtype=numpy.float32) + glow, 0, 255).astype(numpy.uint8))
    image.resize((width, height), Image.LANCZOS).save(out_path)
    print("Rendered", out_path)


if __name__ == "__main__":
    main()
