"""Headless island environment renderer (docs/DEPTH-CONTRACT.md §54).

Renders a scene exported by tools/dump-environment.luau: the forged ground top
(per-vertex colours and smooth normals), the dressing the tier shows (the
art/*.obj masters with the forge's smooth corner normals, tinted like the
forge), the hull meshes on their slots, building meshes and every other part
as a primitive. Gouraud-shaded Lambert light with a soft haze toward the
horizon. No Roblox materials, shadows or Future lighting: judge those in Studio.

    lune run tools/dump-environment.luau "Windpine Grove" /tmp/windpine.json
    python3 tools/render-environment.py /tmp/windpine.json out.png \
        --eye -620,90,-260 --at -500,10,-160 --fov 50 [--size 1600x900]
"""
import importlib.util
import json
import math
import os
import sys

import numpy
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


icons = load("render_icons", os.path.join(ROOT, "art", "render-icons.py"))
town = load("render_town", os.path.join(ROOT, "tools", "render-town.py"))


def hex_rgb(h):
    return numpy.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)])


def main():
    args = sys.argv[1:]
    scene_path, out_path = args[0], args[1]
    opts = {"eye": "0,80,140", "at": "0,0,0", "fov": "50", "size": "1600x900"}
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
    sky_top, sky_bottom = (0.42, 0.66, 0.92), (0.83, 0.91, 0.97)
    pixels = numpy.zeros((H, W, 3), dtype=numpy.uint8)
    for row in range(H):
        t = row / H
        pixels[row, :] = [int(255 * (sky_top[k] * (1 - t) + sky_bottom[k] * t)) for k in range(3)]
    zbuffer = numpy.full((H, W), numpy.inf)
    sun = numpy.array([0.45, 0.8, 0.35])
    sun /= numpy.linalg.norm(sun)
    haze = numpy.array(sky_bottom) * 255

    def project(p):
        rel = p - eye
        depth = rel @ forward
        if depth < 0.5:
            return None
        return (W / 2 + (rel @ right) / depth * focal * H / 2, H / 2 - (rel @ up) / depth * focal * H / 2, -1 / depth)

    def shade(colour, normal, point):
        n = normal / (numpy.linalg.norm(normal) or 1)
        if n @ (eye - point) < 0:
            n = -n
        light = 0.52 + 0.58 * max(0.0, float(n @ sun)) + 0.08 * max(0.0, float(n[1]))
        c = numpy.clip(colour * 255 * light, 0, 255)
        fog = min(0.55, max(0.0, (numpy.linalg.norm(point - eye) - 140) / 900))
        return c * (1 - fog) + haze * fog

    def draw(points, colours, normals):
        projected = [project(p) for p in points]
        if any(p is None for p in projected):
            return
        shaded = [tuple(shade(colours[k], normals[k], points[k])) for k in range(3)]
        icons.rasterise(pixels, zbuffer, projected, shaded)

    with open(scene_path) as handle:
        scene = json.load(handle)
    palette = icons.read_palette()
    cache = {}

    def obj(name):
        if name not in cache:
            vertices, faces, meta = icons.read_obj(name)
            normals = icons.sphere_normals(vertices, faces, meta, icons.corner_normals(vertices, faces, meta["smooth"]))
            v = numpy.array(vertices)
            cache[name] = (v, faces, meta, normals, v.min(axis=0), v.max(axis=0))
        return cache[name]

    colour_cache = {}

    def draw_mesh(name, tint_hex, place):
        v, faces, meta, normals, lo, hi = obj(name)
        tint = hex_rgb(tint_hex) if tint_hex else (hex_rgb(meta["tint"]) if meta["tint"] else None)
        shades = icons.tint_shades(tuple(tint)) if tint is not None else {}
        key = (name, tint_hex)
        if key not in colour_cache:
            # §54 QC A1: the forge's per-vertex colour (family diffusion, AO, mottling).
            colour_cache[key] = icons.vertex_colours([tuple(p) for p in v], faces, meta, lambda m: shades.get(m) or palette[m])
        corner_colours = colour_cache[key]
        world, rot = place(v, lo, hi)
        for index, (ids, material) in enumerate(faces):
            ns = [rot @ numpy.array(n) for n in normals[index]]
            draw([world[i] for i in ids], [numpy.array(c) for c in corner_colours[index]], ns)

    for g in scene.get("surfaces", []):
        verts = numpy.array(g["vertices"])
        cols = [numpy.array(c) for c in g["colors"]]
        nors = [numpy.array(n) for n in g["normals"]]
        for f in g["faces"]:
            ids = [i - 1 for i in f]
            draw([verts[i] for i in ids], [cols[i] for i in ids], [nors[i] for i in ids])
    for m in scene["meshes"]:
        pos, rot = town.transform(m["cf"])

        def place(v, lo, hi, m=m, pos=pos, rot=rot):
            flo, fhi = (numpy.array(m["fit"][0]), numpy.array(m["fit"][1])) if m.get("fit") else (lo, hi)
            k = numpy.array(m["box"]) / (fhi - flo)
            local = (v - (flo + fhi) / 2) * k
            return (rot @ local.T).T + pos, rot
        draw_mesh(m["shape"], m.get("tint"), place)
    for item in scene["items"]:
        pos, rot = town.transform(item["cf"])

        def place(v, lo, hi, item=item, pos=pos, rot=rot):
            return (rot @ (v * item["scale"]).T).T + pos, rot
        draw_mesh(item["shape"], item["tint"], place)
    for part in scene["boxes"]:
        pos, rot = town.transform(part["cf"])
        size = part["size"]
        tris = town.cylinder_tris(size) if part["kind"] == "cylinder" else town.ball_tris(size) if part["kind"] == "ball" else town.box_tris(size)
        colour = hex_rgb(part["color"])
        for tri in tris:
            pts = [(rot @ numpy.array(p)) + pos for p in tri]
            n = numpy.cross(pts[1] - pts[0], pts[2] - pts[0])
            if numpy.linalg.norm(n) < 1e-9:
                continue
            draw(pts, [colour] * 3, [n] * 3)
    Image.fromarray(pixels).resize((width, height), Image.LANCZOS).save(out_path)
    print("Rendered", out_path)


if __name__ == "__main__":
    main()
