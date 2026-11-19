# Original material tiles

The five PNGs are original generated masters. `../MaterialArt.lua` reproduces the loom tile procedurally in one cached 128×128 client EditableImage. GUI consumers share its Content; unsupported allocation returns nil so the interface can retain its flat/vector design.

Roblox asset upload was attempted through the native Studio upload tool. The cloud instance could not read the texture-only loopback URLs, and rejected immutable raw GitHub URLs as untrusted. No asset IDs were returned and no permission boundary was bypassed. The temporary local HTTP server was stopped.

Timber, shale, meadow and brass remain source artwork pending authorized Roblox asset import. World surfaces currently retain their native materials. No blank variants, global MaterialService overrides or per-face texture instances are installed. Once uploaded through an authorized path, bake MaterialVariants into MaterialService at authoring time and map only game-owned surfaces: the engine marks BaseMaterial/ColorMap authoring properties as Plugin Security. Preserve part colors and avoid avatars, transparent surfaces, Neon, Glass and combat telegraphs.

Reference: [MaterialVariant](https://create.roblox.com/docs/reference/engine/classes/MaterialVariant), [EditableImage](https://create.roblox.com/docs/reference/engine/classes/EditableImage).
