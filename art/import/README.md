# Permanent original mesh import

`Aether-Isles-Originals.glb` contains all 86 original OBJ shapes, individually named, with 26,424 indexed triangles and 44 used source material definitions (the 20 world/creature props, 27 item icons and the `OreCluster` resource polish from the Depth update, plus the 38 Wave-4 world meshes from `art/world-shapes.cjs` that `mesh.server.lua` forges at runtime). No external textures, libraries, or runtime EditableMesh allocation is required by the file. This is an import-ready artifact, not an uploaded Roblox asset or an already integrated game template.

Regenerate and verify from the repository root (the prop generator writes the OBJ masters, the import generator rebuilds this bundle; `verify-import.cjs` runs in every build and fails if any OBJ is missing from the GLB):

```powershell
node art/generate-props.cjs
node art/generate-import.cjs
node art/generate-import.cjs --check
node art/import/verify-import.cjs
```

The generator preserves source positions, local origins, triangle winding and material assignment. Normals are normalized flat face normals; coplanar vertices are indexed together. Colors from the source MTL palettes are treated as sRGB and converted to linear glTF material factors. Materials are opaque, double-sided, nonmetallic, with roughness 0.72. This retains thin original shapes; visual review may disable double-sided rendering on closed meshes later.

Distances are meters: each source stud becomes 0.28 meters. Axes remain right-handed and +Y up with source X/Z unchanged; no automatic facing rotation is applied. All nodes intentionally retain their original local origin and overlap at the scene origin: this is a template library, not a staged diorama. `manifest.json` records each source hash, bounds in studs, material counts and the final GLB hash. The independent binary checker compares every triangle against the OBJ, including winding and material, and checks normals, indices, bounds and unit conversion. These checks do not replace visual inspection in Studio or an official glTF validator.

## Studio import results

A local blank-place import of the earlier 20-shape bundle produced 20 models and 88 MeshParts at the expected scale. The importer discarded the visible palette and set each part to gray. Each part matched the extents of its source GLB primitive to within 0.0001 stud. The local color-restored candidate sets each MeshPart's Color from the corresponding source MTL color. For a production export, compare bounds before applying the source color, then verify the palette in Studio.

Even with **Upload to Roblox** disabled, Studio serialized nonzero mesh references. Production asset ownership and experience access still need verification after an authorized import.

## One-time authorized Studio import

1. Open the intended published Aether Isles place in authenticated Studio. Use **File → Import** and select this GLB.
2. Set **Scale Unit: Meter**, scale factor **1**, and retain imported pivots. Keep **Merge Meshes disabled** to preserve the 86 template names. Names of mesh definitions end in `Geometry` so they do not collide with node names.
3. Select the correct creator, enable **Upload to Roblox** and **Add to Workspace**, inspect the preview, and import. This step uploads assets and needs the creator's authorization. If any material or permission fails, resolve it before exporting templates.
4. Compare each imported object's dimensions with `manifest.json` (`max - min`), especially Tidewing and ObservatoryArch. Confirm +Y up, intended forward direction, palette, thin fins/leaves, and hard edges. Multiple material primitives may become multiple child MeshParts: keep each shape's enclosing Model intact. Avoid manually scaling individual parts.
5. Move the 86 shape templates into a Folder named `AetherMeshTemplates`. Preserve each original shape name and source pivot. Anchor parts; disable CanCollide, CanTouch and CanQuery for display-only templates. Keep functional collision in the game's existing collision geometry.
6. Save that Folder as a local **Roblox Model** (`.rbxm`, or `.rbxmx`) after mesh uploads finish. Inspect every MeshPart for a persistent mesh asset reference and test after reopening Studio. Never export only transient EditableMesh-backed instances and assume they became permanent assets.

## Reproducible Rojo integration after import

Export the raw Studio library as one `.rbxm` model. From the repository root, use Lune to prepare a separate template folder with the original colors, shape coordinates and pivots. The converter checks each mesh name, orientation and dimensions before writing the output and verifies that the result deserializes.

```powershell
lune run art/import/prepare-templates.luau RawImport.rbxm AetherMeshTemplates.rbxm
```

Save the authorized export as `art/import/AetherMeshTemplates.rbxm`, commit it, and map it under ReplicatedStorage in `default.project.json`:

```json
"AetherMeshTemplates": { "$path": "art/import/AetherMeshTemplates.rbxm" }
```

Do not add this mapping until that export actually exists. The runtime should clone the named Model, apply its intended pivot/scale, and retain the game's existing fallback when a template is absent. Asset IDs must reference assets available to the experience; a model asset ID is not a mesh ID. Rebuild the place and reopen it to validate serialized mesh content; do not rely on live sync changing protected mesh properties. This pipeline intentionally does not edit the current project or remove its fallback before imported templates are available.

Sources: [Roblox Importer](https://create.roblox.com/docs/studio/importer), [Roblox units](https://create.roblox.com/docs/physics/units), [MeshScaleUnit](https://create.roblox.com/docs/reference/engine/enums/MeshScaleUnit), [glTF 2.0](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html), [Rojo model files and sync limits](https://rojo.space/docs/v7/sync-details/).

## Item icons and the tint slot

`art/generate-props.cjs` also authors the Depth item icons consumed by the UI through `ReplicatedStorage.AetherArt` (`art/PropCatalog.lua`). Each icon stays at or below 120 triangles (the generator fails the run otherwise) because the UI draws every triangle as two WedgeParts. Fronts face -Z, matching the thumbnail camera.

- `Catalog.tintIndex` (11, `Shade11` in `AetherPalette.mtl`, stored as neutral silver `D9DFE6`) marks the "material" faces: blades, armour plates, ore crystals, potion liquid, accessory gems. The UI recolours those faces with the item's AetherData `color`; handles (12), glints (13), leaves (14) and gold trims keep fixed palette colours.
- `Catalog.iconShape(itemDef)` returns the shape for any `Data.Items` definition: bespoke legacy ids first (Pickaxe, Blade/Stormblade, Skyplate, Tonic, AlloyIngot, AetherIngot, Fish, Moonbloom, Aetherite/Shard/Stormglass → AetherCrystal, Timber → TimberBundle), then weapon → Sword, armour by slot → Helm/Chestplate/Greaves/Boots, tools by `toolKind` → ForgedPickaxe/Hatchet/Rod/Hoe, resources by skill → OreChunk/Log/Finfish/CropSheaf, consumables by category → Potion/Meal/Feast, accessories by id → Ring/Amulet/Circlet/Seal/Charm, pets → PetEgg, materials by id → Ingot/DustPile/EssenceOrb/Feather/HideRoll/Seal.
- World sculptures may set a `Tint` Color3 attribute next to `Shape`; `mesh.client.lua` then recolours that shape's tint faces (one cached prototype per shape, scale and tint).
- `OreCluster` is not an icon: `mesh.client.lua` seats it, tinted with the ore colour, on Mining gather nodes that have no sculpture of their own (at most 64 nodes, one prototype per ore, bounded three-part fallback without EditableMesh).

Review silhouettes headlessly with the Pillow/numpy renderer, which mirrors the UI camera and substitutes a sample tint (`art/previews/icons-depth-sheet.png` was produced this way):

```powershell
python3 art/render-icons.py art/previews/icons-depth-sheet.png Sword:F2C14E Helm:D4A84B OreChunk:B87333 ...
```
