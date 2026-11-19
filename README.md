# Aether Isles

An original Roblox floating-island RPG, built from Luau source with Rojo. The local game includes gathering, crafting, persistent workers, Warden hunts, a cooperative Observatory expedition, private islands and shared homesteads.

This is an unfinished development build. Engine playtesting, economy concurrency, device usability and the broader original feature scope are tracked in [PROJECT-STATUS.md](PROJECT-STATUS.md) and [QC-REVIEW.md](QC-REVIEW.md).

## Build locally

Use PowerShell 7 on Windows:

```powershell
./scripts/install-tools.ps1
./build.ps1 -ToolDirectory "$PWD/.tools"
./scripts/verify-release.ps1
./.tools/lune.exe run scripts/verify-workflows.luau
```

The installer selects Lune 0.11.1 and Rojo 7.7.1 release archives and verifies the upstream SHA256 asset digest. Existing verified tools can instead be supplied through `-ToolDirectory`. Open the resulting `Aether-Isles.rbxl` in Roblox Studio. Build output is generated, not committed.

## GitHub

Repository: [Matthew-Uhlar/RobloxMMO](https://github.com/Matthew-Uhlar/RobloxMMO).

Pushes and pull requests run tests and upload a downloadable place artifact. **Publish Roblox place** is a separate manual workflow; it rebuilds and tests the selected default-branch revision before uploading to the verified new Aether Isles destination (universe `10777817254`, place `73453386951995`). It does not create an experience or change public audience access.

See [PUBLISHING.md](PUBLISHING.md) for account setup, credentials, deployment, verification and recovery. Never put API keys or Roblox cookies in source, issues, command-line arguments or screenshots.

The new experience was created privately in Studio on November 19, 2026. No destination variables are needed: add only the Roblox credential secret `ROBLOX_API_KEY` for deployment. [Open the game page](https://www.roblox.com/games/73453386951995) (access remains private until configured).


Source and workflows are uploaded. [GitHub CI run 44492070676](https://github.com/Matthew-Uhlar/RobloxMMO/actions/runs/44492070676) passed tool installation, game tests/build, release validation and artifact upload for commit `975be9c88688def742f15a8b30d91b29c4824588`. Download the `Aether-Isles-975be9c88688def742f15a8b30d91b29c4824588` artifact from that run. Roblox API deployment is still separate.

