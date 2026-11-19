# Aether Isles

An original Roblox floating-island RPG, built from Luau source with Rojo. The local game includes gathering, crafting, persistent workers, Warden hunts, a cooperative Observatory expedition, private islands and shared homesteads. The latest source also includes revision-checked bank transfers and a player market with priced three-unit asks and maximum-price purchases.

The **Depth** update adds OSRS-style 1–99 skills with tiered resources and gear, SkyBlock-style stats, collections, accessories, pets and slayers, real-time combat, four new regions and a rebuilt menu atlas — see [PROJECT-STATUS.md](PROJECT-STATUS.md) and [docs/DEPTH-CONTRACT.md](docs/DEPTH-CONTRACT.md).

This is an unfinished development build. Recorded local Studio smoke checks, remaining economy concurrency/device testing and the broader original feature scope are tracked in [PROJECT-STATUS.md](PROJECT-STATUS.md) and [QC-REVIEW.md](QC-REVIEW.md).

## Build locally

Use PowerShell 7 on Windows with Node.js installed. Node verifies the original mesh bundle as part of the build.

On Linux/macOS with Lune 0.11.1 and Rojo 7.7.1 on PATH (`cargo install lune --version 0.11.1 --locked` and `cargo install rojo --version 7.7.1 --locked`), run `./scripts/build.sh`.

```powershell
./scripts/install-tools.ps1
./build.ps1 -ToolDirectory "$PWD/.tools"
./scripts/verify-release.ps1
./.tools/lune.exe run scripts/verify-workflows.luau
```

The installer selects Lune 0.11.1 and Rojo 7.7.1 release archives and verifies the upstream SHA256 asset digest. Existing verified tools can instead be supplied through `-ToolDirectory`. Open the resulting `Aether-Isles.rbxl` in Roblox Studio. Build output is generated, not committed.

## GitHub

Repository: [Matthew-Uhlar/RobloxMMO](https://github.com/Matthew-Uhlar/RobloxMMO).

Pushes and pull requests run tests and upload a downloadable place artifact. The separate **Publish Roblox place** workflow is configured to run automatically after relevant gameplay changes reach `main`; a manual run on `main` remains available. It rebuilds and tests the selected revision before uploading to universe `10777817254`, place `73453386951995`. Deployment requires the Roblox credential described below. Neither CI success nor an automatic trigger proves that an upload completed, and the workflow does not change audience settings.

See [PUBLISHING.md](PUBLISHING.md) for account setup, credentials, deployment, verification and recovery. Never put API keys or Roblox cookies in source, issues, command-line arguments or screenshots.

The experience was created privately on November 19, 2026. Open Cloud confirms **Public** visibility, and Studio displays **ages 16+**. A separate-account player join remains unverified. No destination variables are needed; configure the `ROBLOX_API_KEY` environment secret for deployment. [Open the game page](https://www.roblox.com/games/73453386951995).

The last cloud code explicitly confirmed by the primary agent is the **Skyreach** update. Deployment of the later Observatory, bank and trade updates is **unknown until a publish receipt/version check confirms it**. Their source and local Studio verification must not be described as a confirmed cloud release.


Source and workflows are uploaded. [GitHub CI run 44492070676](https://github.com/Matthew-Uhlar/RobloxMMO/actions/runs/44492070676) passed tool installation, game tests/build, release validation and artifact upload for commit `975be9c88688def742f15a8b30d91b29c4824588`. Download the `Aether-Isles-975be9c88688def742f15a8b30d91b29c4824588` artifact from that run. This historical run does not establish deployment of the latest source or continued artifact availability.


## Current verification and original art

Latest integrated checks: **371 gameplay, 10,702 world/mesh, 45 expedition and 47 co-op checks**, plus **nine source-matching compiled scripts/modules**. Local Studio smoke covered compact menus, ration use, bank amounts and a seeded priced-market buy/stale-limit refund. These checks do not establish live cross-server economy safety or physical-device performance.

The [mesh import bundle](art/import/README.md) contains 20 original shapes. A blank Studio import preserved dimensions across 88 mesh parts. The importer displayed them in gray. A local candidate restores their original colors, and production access still needs verification. Runtime meshes retain their geometric fallback. EditableImage allocation failed in local smoke; original vector icons, stitched trim and flat menu artwork remain available without it.
