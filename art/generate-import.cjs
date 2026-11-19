// Dependency-free, deterministic OBJ/MTL -> glTF 2.0 binary. Run with Node.
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const assert = require('assert');

const SOURCE_DIRECTORY = __dirname;
const OUTPUT_DIRECTORY = path.join(SOURCE_DIRECTORY, 'import');
const METERS_PER_STUD = 0.28;

function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function readSource(file) {
  const vertices = [];
  const faces = [];
  const materials = {};
  let material;
  let library;

  const objText = fs.readFileSync(path.join(SOURCE_DIRECTORY, file), 'utf8');
  for (const line of objText.split(/\r?\n/)) {
    const [operation, ...values] = line.trim().split(/\s+/);
    if (operation === 'mtllib') library = values.join(' ');
    if (operation === 'v') {
      assert(values.length === 3);
      vertices.push(values.map(Number));
    }
    if (operation === 'usemtl') material = values[0];
    if (operation === 'f') {
      assert(values.length === 3, 'Source must already be triangulated');
      const ids = values.map(value => Number(value.split('/')[0]) - 1);
      assert(ids.every(id => Number.isInteger(id) && id >= 0 && id < vertices.length));
      faces.push({ ids, material });
    }
  }

  let currentMaterial;
  const mtlText = fs.readFileSync(path.join(SOURCE_DIRECTORY, library), 'utf8');
  for (const line of mtlText.split(/\r?\n/)) {
    const [operation, ...values] = line.trim().split(/\s+/);
    if (operation === 'newmtl') currentMaterial = values[0];
    if (operation === 'Kd') materials[currentMaterial] = values.map(Number);
  }

  assert(vertices.flat().every(Number.isFinite));
  assert(faces.every(face => materials[face.material]));
  return { file, name: path.basename(file, '.obj'), vertices, faces, materials, library };
}

function bounds(points) {
  return {
    min: [0, 1, 2].map(axis => Math.min(...points.map(point => point[axis]))),
    max: [0, 1, 2].map(axis => Math.max(...points.map(point => point[axis]))),
  };
}

function faceNormal(a, b, c) {
  const edgeAB = b.map((value, axis) => value - a[axis]);
  const edgeAC = c.map((value, axis) => value - a[axis]);
  const normal = [
    edgeAB[1] * edgeAC[2] - edgeAB[2] * edgeAC[1],
    edgeAB[2] * edgeAC[0] - edgeAB[0] * edgeAC[2],
    edgeAB[0] * edgeAC[1] - edgeAB[1] * edgeAC[0],
  ];
  const length = Math.hypot(...normal);
  assert(length > 1e-10, 'Degenerate triangle');
  return normal.map(value => value / length);
}

function createDocument() {
  // Property insertion order is part of this deterministic artifact format.
  return {
    asset: { version: '2.0', generator: 'Aether Isles original import pipeline 1' },
    scene: 0,
    scenes: [{ name: 'AetherOriginals', nodes: [] }],
    nodes: [],
    meshes: [],
    materials: [],
    accessors: [],
    bufferViews: [],
    buffers: [],
  };
}

function appendAccessor(document, binary, values, type, isIndex = false) {
  const components = type === 'VEC3' ? 3 : 1;
  const componentBytes = isIndex ? 2 : 4;
  const bytes = Buffer.alloc(values.length * componentBytes);
  values.forEach((value, index) => {
    if (isIndex) bytes.writeUInt16LE(value, index * 2);
    else bytes.writeFloatLE(value, index * 4);
  });

  const viewIndex = document.bufferViews.length;
  document.bufferViews.push({
    buffer: 0,
    byteOffset: binary.length,
    byteLength: bytes.length,
    target: isIndex ? 34963 : 34962,
  });
  binary.chunks.push(bytes);
  binary.length += bytes.length;
  const padding = (4 - binary.length % 4) % 4;
  if (padding) {
    binary.chunks.push(Buffer.alloc(padding));
    binary.length += padding;
  }

  const accessor = {
    bufferView: viewIndex,
    componentType: isIndex ? 5123 : 5126,
    count: values.length / components,
    type,
  };
  if (type === 'VEC3') {
    const points = [];
    for (let index = 0; index < values.length; index += 3) {
      points.push(values.slice(index, index + 3).map(Math.fround));
    }
    Object.assign(accessor, bounds(points));
  }
  return document.accessors.push(accessor) - 1;
}

function srgbToLinear(channel) {
  return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
}

function addMaterial(document, materialIds, source, materialName) {
  const key = source.library + ':' + materialName;
  if (!materialIds.has(key)) {
    materialIds.set(key, document.materials.length);
    document.materials.push({
      name: key,
      pbrMetallicRoughness: {
        baseColorFactor: [...source.materials[materialName].map(srgbToLinear), 1],
        metallicFactor: 0,
        roughnessFactor: 0.72,
      },
      doubleSided: true,
      extras: { sourceSrgb: source.materials[materialName] },
    });
  }
  return materialIds.get(key);
}

function buildPrimitive(document, binary, source, materialName, materialIndex) {
  const positions = [];
  const normals = [];
  const indices = [];
  const verticesByNormal = new Map();

  for (const face of source.faces.filter(face => face.material === materialName)) {
    const normal = faceNormal(...face.ids.map(id => source.vertices[id]));
    for (const id of face.ids) {
      // Share coplanar corners while retaining flat normals at hard edges.
      const key = id + ':' + normal.map(value => value.toFixed(10)).join(',');
      if (!verticesByNormal.has(key)) {
        verticesByNormal.set(key, positions.length / 3);
        positions.push(...source.vertices[id].map(value => value * METERS_PER_STUD));
        normals.push(...normal);
      }
      indices.push(verticesByNormal.get(key));
    }
  }

  assert(positions.length / 3 < 65536);
  return {
    attributes: {
      POSITION: appendAccessor(document, binary, positions, 'VEC3'),
      NORMAL: appendAccessor(document, binary, normals, 'VEC3'),
    },
    indices: appendAccessor(document, binary, indices, 'SCALAR', true),
    material: materialIndex,
    mode: 4,
  };
}

function addShape(document, binary, materialIds, source) {
  const primitives = [];
  const materialNames = [...new Set(source.faces.map(face => face.material))].sort();
  for (const materialName of materialNames) {
    const materialIndex = addMaterial(document, materialIds, source, materialName);
    primitives.push(buildPrimitive(document, binary, source, materialName, materialIndex));
  }

  document.scenes[0].nodes.push(document.nodes.length);
  document.nodes.push({
    name: source.name,
    mesh: document.meshes.length,
    extras: {
      source: source.file,
      studBounds: bounds(source.vertices),
      metersPerStud: METERS_PER_STUD,
    },
  });
  document.meshes.push({ name: source.name + 'Geometry', primitives });
}

function encodeGlb(document, binary) {
  document.buffers.push({ byteLength: binary.length });
  const binaryBytes = Buffer.concat(binary.chunks);
  const jsonBytes = Buffer.from(JSON.stringify(document));
  const jsonPadding = Buffer.alloc((4 - jsonBytes.length % 4) % 4, 32);

  // The first 20 bytes combine the GLB header and JSON chunk header.
  const header = Buffer.alloc(20);
  header.writeUInt32LE(0x46546c67);
  header.writeUInt32LE(2, 4);
  header.writeUInt32LE(28 + jsonBytes.length + jsonPadding.length + binaryBytes.length, 8);
  header.writeUInt32LE(jsonBytes.length + jsonPadding.length, 12);
  header.writeUInt32LE(0x4e4f534a, 16);

  const binaryHeader = Buffer.alloc(8);
  binaryHeader.writeUInt32LE(binaryBytes.length);
  binaryHeader.writeUInt32LE(0x004e4942, 4);
  return Buffer.concat([header, jsonBytes, jsonPadding, binaryHeader, binaryBytes]);
}

function createManifest(sources, document, glb) {
  return {
    format: 1,
    metersPerStud: METERS_PER_STUD,
    axes: 'Right-handed +Y up; source X/Z and local origin preserved (no rotation/reflection).',
    glbSha256: sha256(glb),
    materials: document.materials.length,
    triangles: sources.reduce((total, source) => total + source.faces.length, 0),
    models: sources.map(source => ({
      name: source.name,
      source: source.file,
      sourceSha256: sha256(fs.readFileSync(path.join(SOURCE_DIRECTORY, source.file))),
      materialSource: source.library,
      materialSha256: sha256(fs.readFileSync(path.join(SOURCE_DIRECTORY, source.library))),
      vertices: source.vertices.length,
      triangles: source.faces.length,
      boundsStuds: bounds(source.vertices),
      trianglesByMaterial: Object.fromEntries(
        [...new Set(source.faces.map(face => face.material))].sort().map(material => [
          material,
          source.faces.filter(face => face.material === material).length,
        ]),
      ),
    })),
  };
}

function main() {
  const files = fs.readdirSync(SOURCE_DIRECTORY).filter(file => file.endsWith('.obj')).sort();
  const sources = files.map(readSource);
  const document = createDocument();
  const binary = { chunks: [], length: 0 };
  const materialIds = new Map();
  for (const source of sources) addShape(document, binary, materialIds, source);

  const glb = encodeGlb(document, binary);
  const manifest = createManifest(sources, document, glb);
  const manifestText = JSON.stringify(manifest, null, 2) + '\n';
  const target = path.join(OUTPUT_DIRECTORY, 'Aether-Isles-Originals.glb');
  const manifestPath = path.join(OUTPUT_DIRECTORY, 'manifest.json');

  if (process.argv.includes('--check')) {
    assert(fs.readFileSync(target).equals(glb), 'GLB differs from deterministic source build');
    assert.strictEqual(fs.readFileSync(manifestPath, 'utf8'), manifestText);
  } else {
    fs.mkdirSync(OUTPUT_DIRECTORY, { recursive: true });
    fs.writeFileSync(target, glb);
    fs.writeFileSync(manifestPath, manifestText);
  }
  console.log(`${sources.length} shapes, ${manifest.triangles} triangles, ${manifest.materials} source materials, ${glb.length} bytes; SHA256 ${manifest.glbSha256}`);
}

main();
