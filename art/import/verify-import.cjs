// Independent binary reader and source parity check; no generator imports or dependencies.
'use strict';

const fs = require('fs');
const path = require('path');
const assert = require('assert');

const SOURCE_DIRECTORY = path.join(__dirname, '..');
const METERS_PER_STUD = 0.28;
const near = (actual, expected) => Math.abs(actual - expected) < 0.00002;

function integer(value, minimum, label) {
  assert(Number.isSafeInteger(value) && value >= minimum, `${label} must be an integer >= ${minimum}`);
  return value;
}

function reference(items, index, label) {
  integer(index, 0, label);
  assert(index < items.length, `${label} is out of range`);
  return items[index];
}

function parseGlb(bytes) {
  assert(bytes.length >= 28, 'GLB is shorter than its headers');
  assert.strictEqual(bytes.readUInt32LE(0), 0x46546c67, 'GLB magic');
  assert.strictEqual(bytes.readUInt32LE(4), 2, 'GLB version');
  assert.strictEqual(bytes.readUInt32LE(8), bytes.length, 'GLB total length');

  const jsonLength = bytes.readUInt32LE(12);
  assert.strictEqual(jsonLength % 4, 0, 'JSON chunk alignment');
  assert.strictEqual(bytes.readUInt32LE(16), 0x4e4f534a, 'JSON chunk type');
  assert(20 + jsonLength + 8 <= bytes.length, 'JSON chunk exceeds file');
  const document = JSON.parse(bytes.subarray(20, 20 + jsonLength).toString('utf8'));
  const binaryStart = 28 + jsonLength;
  const binaryLength = bytes.readUInt32LE(20 + jsonLength);
  assert.strictEqual(bytes.readUInt32LE(24 + jsonLength), 0x004e4942, 'BIN chunk type');
  assert.strictEqual(binaryLength % 4, 0, 'BIN chunk alignment');
  assert.strictEqual(binaryLength, bytes.length - binaryStart, 'BIN chunk length');
  assert.strictEqual(document.asset.version, '2.0');
  assert.strictEqual(document.buffers.length, 1, 'Expected one embedded buffer');
  assert.strictEqual(document.buffers[0].uri, undefined, 'External buffers are unsupported');
  assert.strictEqual(document.buffers[0].byteLength, binaryLength, 'Embedded buffer length');
  return { document, binaryStart, bytes };
}

function validateBufferViews(document) {
  for (const [index, view] of document.bufferViews.entries()) {
    assert.strictEqual(view.buffer, 0, `Buffer view ${index} buffer reference`);
    const offset = integer(view.byteOffset ?? 0, 0, `Buffer view ${index} offset`);
    const length = integer(view.byteLength, 1, `Buffer view ${index} length`);
    assert.strictEqual(offset % 4, 0, `Buffer view ${index} alignment`);
    assert(offset + length <= document.buffers[0].byteLength, `Buffer view ${index} exceeds BIN`);
    if (view.byteStride !== undefined) {
      integer(view.byteStride, 4, `Buffer view ${index} stride`);
      assert(view.byteStride <= 252 && view.byteStride % 4 === 0, 'Invalid byte stride');
    }
  }
}

function readAccessor(glb, index) {
  const { document, bytes, binaryStart } = glb;
  const accessor = reference(document.accessors, index, 'Accessor reference');
  const view = reference(document.bufferViews, accessor.bufferView, 'Accessor buffer view');
  assert(['VEC3', 'SCALAR'].includes(accessor.type), 'Unsupported accessor type');
  assert([5126, 5123].includes(accessor.componentType), 'Unsupported component type');
  assert(!accessor.sparse && !accessor.normalized, 'Unexpected sparse or normalized accessor');

  const components = accessor.type === 'VEC3' ? 3 : 1;
  const componentBytes = accessor.componentType === 5126 ? 4 : 2;
  const elementBytes = components * componentBytes;
  const offset = integer(accessor.byteOffset ?? 0, 0, 'Accessor byte offset');
  const count = integer(accessor.count, 1, 'Accessor count');
  const stride = view.byteStride ?? elementBytes;
  assert(stride >= elementBytes, 'Accessor stride is smaller than an element');
  assert.strictEqual(offset % componentBytes, 0, 'Accessor component alignment');
  assert.strictEqual(((view.byteOffset ?? 0) + offset) % componentBytes, 0, 'Absolute component alignment');
  const lastByte = offset + (count - 1) * stride + elementBytes;
  assert(Number.isSafeInteger(lastByte) && lastByte <= view.byteLength, 'Accessor exceeds its buffer view');

  const rows = [];
  for (let rowIndex = 0; rowIndex < count; rowIndex++) {
    const row = [];
    for (let component = 0; component < components; component++) {
      const byteOffset = binaryStart + (view.byteOffset ?? 0) + offset
        + rowIndex * stride + component * componentBytes;
      row.push(componentBytes === 4 ? bytes.readFloatLE(byteOffset) : bytes.readUInt16LE(byteOffset));
    }
    assert(row.every(Number.isFinite), 'Non-finite accessor value');
    rows.push(row);
  }

  if (accessor.min !== undefined || accessor.max !== undefined) {
    assert(accessor.min?.length === components && accessor.max?.length === components, 'Accessor bounds dimensions');
    for (let axis = 0; axis < components; axis++) {
      assert.strictEqual(Math.min(...rows.map(row => row[axis])), accessor.min[axis], 'Accessor minimum');
      assert.strictEqual(Math.max(...rows.map(row => row[axis])), accessor.max[axis], 'Accessor maximum');
    }
  }
  return rows;
}

function triangleKey(points, material) {
  const vertices = points.map(point => point.map(value => Math.round(value * 10000)).join(','));
  // Cyclic permutations preserve winding; reversed permutations do not.
  const rotations = [
    vertices.join(';'),
    [vertices[1], vertices[2], vertices[0]].join(';'),
    [vertices[2], vertices[0], vertices[1]].join(';'),
  ];
  return material + '|' + rotations.sort()[0];
}

function readObj(name) {
  const text = fs.readFileSync(path.join(SOURCE_DIRECTORY, name + '.obj'), 'utf8');
  const vertices = [];
  const expectedTriangles = [];
  let material;
  let library;
  for (const line of text.split(/\r?\n/)) {
    const [operation, ...values] = line.trim().split(/\s+/);
    if (operation === 'v') vertices.push(values.map(Number));
    if (operation === 'mtllib') library = values.join(' ');
    if (operation === 'usemtl') material = values[0];
    if (operation === 'f') {
      assert.strictEqual(values.length, 3, 'Source face is not a triangle');
      const points = values.map(value => vertices[Number(value.split('/')[0]) - 1]);
      assert(points.every(point => point?.length === 3), 'Source face index');
      expectedTriangles.push(triangleKey(points, library + ':' + material));
    }
  }
  return { vertices, expectedTriangles, library };
}

function readPalette(library) {
  const palette = new Map();
  let name;
  const text = fs.readFileSync(path.join(SOURCE_DIRECTORY, library), 'utf8');
  for (const line of text.split(/\r?\n/)) {
    const [operation, ...values] = line.trim().split(/\s+/);
    if (operation === 'newmtl') name = values[0];
    if (operation === 'Kd') {
      const channels = values.map(Number);
      assert(name && channels.length === 3, 'Source diffuse color definition');
      assert(channels.every(channel => Number.isFinite(channel) && channel >= 0 && channel <= 1));
      palette.set(library + ':' + name, channels);
    }
  }
  return palette;
}

function verifyMaterial(material, sourcePalette) {
  const srgb = sourcePalette.get(material.name);
  assert(srgb, `Material ${material.name} is absent from the source MTL`);
  const pbr = material.pbrMetallicRoughness;
  assert(Array.isArray(pbr?.baseColorFactor) && pbr.baseColorFactor.length === 4, 'RGBA base color required');
  for (let channel = 0; channel < 3; channel++) {
    const expected = srgb[channel] <= 0.04045
      ? srgb[channel] / 12.92
      : Math.pow((srgb[channel] + 0.055) / 1.055, 2.4);
    const actual = pbr.baseColorFactor[channel];
    assert(Number.isFinite(actual) && Math.abs(actual - expected) < 1e-12,
      `${material.name} baseColorFactor channel ${channel} differs from source MTL`);
  }
  assert.strictEqual(pbr.baseColorFactor[3], 1, 'Material opacity');
  assert.strictEqual(pbr.metallicFactor, 0, 'Material metallic factor');
  assert.strictEqual(pbr.roughnessFactor, 0.72, 'Material roughness');
  assert.strictEqual(material.doubleSided, true, 'Thin faces must remain double-sided');
  assert.deepStrictEqual(material.extras?.sourceSrgb, srgb, 'Material source-color metadata');
}

function validateScene(document, sourceNames) {
  assert.strictEqual(document.scene, 0, 'Default scene reference');
  assert.strictEqual(document.scenes.length, 1, 'Expected one template scene');
  assert.strictEqual(document.meshes.length, document.nodes.length, 'Expected one mesh per node');
  const names = document.nodes.map(node => node.name);
  assert.deepStrictEqual([...names].sort(), sourceNames, 'Scene must contain every source shape exactly once');
  const sceneNodes = document.scenes[0].nodes;
  assert.strictEqual(sceneNodes.length, document.nodes.length, 'Scene root count');
  assert.strictEqual(new Set(sceneNodes).size, document.nodes.length, 'Duplicate scene root reference');
  for (const index of sceneNodes) reference(document.nodes, index, 'Scene node reference');

  const meshReferences = new Set();
  for (const node of document.nodes) {
    assert(!node.matrix && !node.rotation && !node.translation && !node.scale, 'Unexpected node transform');
    assert(!node.children?.length, 'Template scene must remain flat');
    reference(document.meshes, node.mesh, 'Node mesh reference');
    assert(!meshReferences.has(node.mesh), 'Duplicate mesh reference');
    meshReferences.add(node.mesh);
  }
}

function verifyNormals(points, normals, ids) {
  const edgeAB = points[1].map((value, axis) => value - points[0][axis]);
  const edgeAC = points[2].map((value, axis) => value - points[0][axis]);
  const normal = [
    edgeAB[1] * edgeAC[2] - edgeAB[2] * edgeAC[1],
    edgeAB[2] * edgeAC[0] - edgeAB[0] * edgeAC[2],
    edgeAB[0] * edgeAC[1] - edgeAB[1] * edgeAC[0],
  ];
  const length = Math.hypot(...normal);
  assert(length > 1e-12, 'Degenerate binary triangle');
  for (const id of ids) {
    assert(near(Math.hypot(...normals[id]), 1), 'Normal must be normalized');
    const alignment = normals[id].reduce((sum, value, axis) => sum + value * normal[axis] / length, 0);
    assert(alignment > 0.99999, 'Normal differs from face winding');
  }
}

function verifyNode(document, accessorRows, node, source) {
  const actualTriangles = [];
  const allPositions = [];
  const mesh = document.meshes[node.mesh];
  assert(mesh.primitives.length > 0, 'Mesh has no primitives');

  for (const primitive of mesh.primitives) {
    assert.strictEqual(primitive.mode, 4, 'Expected triangle primitive');
    const positionAccessor = reference(document.accessors, primitive.attributes.POSITION, 'Position accessor');
    const normalAccessor = reference(document.accessors, primitive.attributes.NORMAL, 'Normal accessor');
    const indexAccessor = reference(document.accessors, primitive.indices, 'Index accessor');
    assert(positionAccessor.type === 'VEC3' && positionAccessor.componentType === 5126, 'Position format');
    assert(normalAccessor.type === 'VEC3' && normalAccessor.componentType === 5126, 'Normal format');
    assert(indexAccessor.type === 'SCALAR' && indexAccessor.componentType === 5123, 'Index format');
    const positions = accessorRows[primitive.attributes.POSITION];
    const normals = accessorRows[primitive.attributes.NORMAL];
    const indices = accessorRows[primitive.indices].flat();
    const material = reference(document.materials, primitive.material, 'Primitive material');
    assert.strictEqual(indices.length % 3, 0, 'Triangle index count');
    assert.strictEqual(normals.length, positions.length, 'Position/normal count');

    for (let index = 0; index < indices.length; index += 3) {
      const ids = indices.slice(index, index + 3);
      assert(ids.every(id => Number.isInteger(id) && id >= 0 && id < positions.length), 'Vertex index range');
      const points = ids.map(id => positions[id]);
      allPositions.push(...points);
      verifyNormals(points, normals, ids);
      const studs = points.map(point => point.map(value => value / METERS_PER_STUD));
      actualTriangles.push(triangleKey(studs, material.name));
    }
  }

  assert.deepStrictEqual(actualTriangles.sort(), source.expectedTriangles.sort(),
    node.name + ' triangle, winding, palette assignment or axes mismatch');
  for (let axis = 0; axis < 3; axis++) {
    assert(near(Math.min(...allPositions.map(point => point[axis])) / METERS_PER_STUD,
      Math.min(...source.vertices.map(point => point[axis]))), node.name + ' minimum bound');
    assert(near(Math.max(...allPositions.map(point => point[axis])) / METERS_PER_STUD,
      Math.max(...source.vertices.map(point => point[axis]))), node.name + ' maximum bound');
  }
  return actualTriangles.length;
}

function main() {
  const target = process.argv[2] || path.join(__dirname, 'Aether-Isles-Originals.glb');
  const glb = parseGlb(fs.readFileSync(target));
  const { document } = glb;
  const sourceNames = fs.readdirSync(SOURCE_DIRECTORY)
    .filter(file => file.endsWith('.obj')).map(file => path.basename(file, '.obj')).sort();
  validateScene(document, sourceNames);
  validateBufferViews(document);
  const accessorRows = document.accessors.map((_, index) => readAccessor(glb, index));

  const sources = new Map(sourceNames.map(name => [name, readObj(name)]));
  const sourcePalette = new Map();
  for (const library of new Set([...sources.values()].map(source => source.library))) {
    for (const [name, color] of readPalette(library)) sourcePalette.set(name, color);
  }
  for (const material of document.materials) verifyMaterial(material, sourcePalette);

  let triangles = 0;
  for (const node of document.nodes) triangles += verifyNode(document, accessorRows, node, sources.get(node.name));
  console.log(`PASS: ${sourceNames.length} nodes / ${triangles} indexed triangles; source winding, axes, actual MTL colors, scene references, normals, units, bounds and binary ranges verified.`);
}

main();
