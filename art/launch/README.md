# Aether Isles launch artwork

- `aether-isles-icon.png`: 512 × 512, square launch icon.
- `aether-isles-thumbnail.png`: 1280 × 720, 16:9 launch thumbnail.

Rebuild from the project root with `node art/generate-launch.cjs`. Requires Node and Windows PowerShell/System.Drawing; no npm dependencies, network access or API keys. The generator loads the existing original OBJ masters and their material palettes, projects and lights their triangles, and renders the composition at 2× resolution before downsampling.

Shown assets: FloatingIslet, AetherCrystal, Surveyor, Lantern, WindpineCrown and Tidewing. Typography uses Windows Georgia and Segoe UI. These are authored promotional compositions from actual project meshes, not gameplay screenshots. No third-party character art is used. Inspect regenerated PNGs if fonts or rendering platforms change.

Both final images were visually inspected for title readability, unclipped main silhouettes, material colors and 16:9/square framing. Cloud layers, stars and the sky glow are generated scene decoration. No Roblox/cloud metadata was changed by the generator.
