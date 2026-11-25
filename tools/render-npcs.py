"""Headless preview of the §52 townsfolk (Pillow + numpy, no Studio).

Reads the JSON from tools/dump-npcs.luau (each rig's primitive parts after a
pose from its trade idle loop, plus the forged outfit pieces with their bone
frames and dyes), draws the parts as boxes / cylinders / balls and the outfit
OBJ masters with crease-angle smoothing, flat Lambert light (no materials,
bloom or shadows: not a Studio capture), and writes a labelled contact sheet.

    lune run tools/dump-npcs.luau /tmp/npcs.json 0
    python3 -I tools/render-npcs.py /tmp/npcs.json OUT.png [--cell N] [--columns N] [--angle three|front|side]
"""
import importlib.util
import sys as _sys
_sys.dont_write_bytecode = True
import json
import math
import os
import sys

import numpy
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "art")
spec = importlib.util.spec_from_file_location("icons", os.path.join(ART, "render-icons.py"))
icons = importlib.util.module_from_spec(spec)
spec.loader.exec_module(icons)
FONT_PATH = "/usr/share/fonts/opentype/inter/Inter-Bold.otf"


def rgb(hex_colour):
    return tuple(int(hex_colour[i:i + 2], 16) / 255 for i in (0, 2, 4))


def frame(components):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = components
    return numpy.array([x, y, z]), numpy.array([[r00, r01, r02], [r10, r11, r12], [r20, r21, r22]])


def box_mesh(size):
    sx, sy, sz = (s / 2 for s in size)
    corners = [(-sx, -sy, -sz), (sx, -sy, -sz), (sx, sy, -sz), (-sx, sy, -sz), (-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz)]
    quads = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (3, 7, 6, 2), (0, 4, 7, 3), (1, 2, 6, 5)]
    faces = []
    for a, b, c, d in quads:
        faces += [([a, b, c], "P"), ([a, c, d], "P")]
    return corners, faces, 0


def cylinder_mesh(size, n=18):
    length, radius = size[0] / 2, min(size[1], size[2]) / 2
    verts, faces = [], []
    for i in range(n):
        a = i * 2 * math.pi / n
        verts += [(-length, math.cos(a) * radius, math.sin(a) * radius), (length, math.cos(a) * radius, math.sin(a) * radius)]
    verts += [(-length, 0, 0), (length, 0, 0)]
    for i in range(n):
        j = (i + 1) % n
        faces += [([2 * i, 2 * j, 2 * j + 1], "P"), ([2 * i, 2 * j + 1, 2 * i + 1], "P"), ([2 * n, 2 * j, 2 * i], "P"), ([2 * n + 1, 2 * i + 1, 2 * j + 1], "P")]
    return verts, faces, 40


def ball_mesh(size, n=10):
    r = min(size) / 2
    verts, faces = [], []
    for i in range(n + 1):
        phi = math.pi * i / n
        for j in range(n):
            theta = 2 * math.pi * j / n
            verts.append((r * math.sin(phi) * math.cos(theta), r * math.cos(phi), r * math.sin(phi) * math.sin(theta)))
    for i in range(n):
        for j in range(n):
            a, b = i * n + j, i * n + (j + 1) % n
            c, d = (i + 1) * n + j, (i + 1) * n + (j + 1) % n
            faces += [([a, c, d], "P"), ([a, d, b], "P")]
    return verts, faces, 50


OBJ_CACHE = {}


def scene(npc):
    meshes = []
    for p in npc["parts"]:
        pos, rot = frame(p["cf"])
        maker = {"Cylinder": cylinder_mesh, "Ball": ball_mesh}.get(p["shape"], box_mesh)
        verts, faces, smooth = maker(p["size"])
        world = [tuple(pos + rot @ numpy.array(v)) for v in verts]
        meshes.append({"vertices": world, "faces": faces, "smooth": smooth, "flat": rgb(p["color"]), "glow": p.get("neon"), "alpha": p.get("alpha", 0)})
    for m in npc["meshes"]:
        if m["shape"] not in OBJ_CACHE:
            OBJ_CACHE[m["shape"]] = icons.read_obj(m["shape"])
        verts, faces, meta = OBJ_CACHE[m["shape"]]
        pos, rot = frame(m["cf"])
        k = m.get("k", 1)
        world = [tuple(pos + rot @ (numpy.array(v) * k)) for v in verts]
        tint = rgb(m["dye"]) if m.get("dye") else (rgb(meta["tint"]) if meta["tint"] else None)
        meshes.append({"vertices": world, "faces": faces, "smooth": meta["smooth"], "tint": tint})
    return meshes


def render(meshes, size, angle, background):
    palette = icons.read_palette()
    allv = [v for m in meshes for v in m["vertices"]]
    low = [min(v[i] for v in allv) for i in range(3)]
    high = [max(v[i] for v in allv) for i in range(3)]
    centre = tuple((low[i] + high[i]) / 2 for i in range(3))
    radius = max(high[i] - low[i] for i in range(3))
    direction = {"three": (0.55, 0.22, -1), "front": (0.02, 0.12, -1), "side": (1, 0.2, -0.1), "back": (-0.4, 0.2, 1)}[angle]
    forward_dir = icons.unit(direction)
    eye = tuple(centre[i] + forward_dir[i] * radius * 2.15 for i in range(3))
    forward = icons.unit(icons.sub(centre, eye))
    right = icons.unit(icons.cross(forward, (0, 1, 0)))
    up = icons.cross(right, forward)
    focal = 1 / math.tan(math.radians(30) / 2)
    light = icons.unit((0.8, 1.5, -1.1))
    fill = icons.unit((-1, 0.3, 0.6))
    scale = size * icons.SUPER
    pixels = numpy.empty((scale, scale, 3), dtype=numpy.uint8)
    top, bottom = background
    for row in range(scale):
        f = row / scale
        pixels[row, :] = [int(top[i] + (bottom[i] - top[i]) * f) for i in range(3)]
    zbuffer = numpy.full((scale, scale), numpy.inf)
    for m in meshes:
        if m.get("alpha", 0) >= 0.5:
            continue
        shades = icons.tint_shades(m["tint"]) if m.get("tint") else {}
        normals = icons.corner_normals(m["vertices"], m["faces"], m["smooth"])
        for (ids, material), corners in zip(m["faces"], normals):
            points = [m["vertices"][i] for i in ids]
            normal = icons.unit(icons.cross(icons.sub(points[1], points[0]), icons.sub(points[2], points[0])))
            middle = tuple(sum(q[i] for q in points) / 3 for i in range(3))
            flip = icons.dot(normal, icons.sub(eye, middle)) < 0
            colour = []
            for corner in corners:
                if m.get("glow"):
                    colour.append(tuple(min(255.0, ch * 255 * 1.1 + 40) for ch in m["flat"]))
                    continue
                base = m["flat"] if "flat" in m else (shades.get(material) or palette[material])
                if flip:
                    corner = (-corner[0], -corner[1], -corner[2])
                shade = 0.42 + 0.62 * max(0.0, icons.dot(corner, light)) + 0.16 * max(0.0, icons.dot(corner, fill))
                colour.append(tuple(min(255.0, ch * 255 * shade) for ch in base))
            projected = []
            for point in points:
                relative = icons.sub(point, eye)
                depth = icons.dot(relative, forward)
                projected.append((scale / 2 + icons.dot(relative, right) / depth * focal * scale / 2,
                                  scale / 2 - icons.dot(relative, up) / depth * focal * scale / 2, depth))
            icons.rasterise(pixels, zbuffer, projected, colour)
    return Image.fromarray(pixels).resize((size, size), Image.LANCZOS)


def main():
    args = sys.argv[1:]
    cell, columns, angle = 220, 7, "three"
    positional = []
    while args:
        a = args.pop(0)
        if a == "--cell":
            cell = int(args.pop(0))
        elif a == "--columns":
            columns = int(args.pop(0))
        elif a == "--angle":
            angle = args.pop(0)
        else:
            positional.append(a)
    source, output = positional[0], positional[1]
    with open(source) as handle:
        npcs = json.load(handle)
    columns = min(columns, len(npcs))
    rows = math.ceil(len(npcs) / columns)
    label_h = 40
    sheet = Image.new("RGB", (columns * (cell + 8) + 8, rows * (cell + label_h + 8) + 8), (14, 20, 28))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype(FONT_PATH, 13)
        small = ImageFont.truetype(FONT_PATH, 11)
    except OSError:
        font = small = ImageFont.load_default()
    for index, npc in enumerate(npcs):
        x, y = 8 + index % columns * (cell + 8), 8 + index // columns * (cell + label_h + 8)
        image = render(scene(npc), cell, angle, ((116, 160, 200), (196, 214, 226)))
        sheet.paste(image, (x, y))
        draw.rectangle([x, y + cell, x + cell, y + cell + label_h - 2], fill=(17, 24, 34))
        draw.rectangle([x, y + cell + label_h - 5, x + cell, y + cell + label_h - 2], fill=tuple(int(npc["accent"][i:i + 2], 16) for i in (0, 2, 4)))
        draw.text((x + 6, y + cell + 3), npc["name"], fill=(255, 230, 166), font=font)
        draw.text((x + 6, y + cell + 20), npc["title"] + "  ·  " + npc["idle"], fill=tuple(int(npc["titleColor"][i:i + 2], 16) for i in (0, 2, 4)), font=small)
    sheet.save(output)
    print("Rendered", len(npcs), "townsfolk to", output)


if __name__ == "__main__":
    main()
