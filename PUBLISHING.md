# Publishing Aether Isles

Aether Isles is public. Roblox Open Cloud returned `PUBLIC` for universe `10777817254` and identified place `73453386951995` as its start place. Studio shows **ages 16+**. A player join from a separate account is still unverified. [Game page](https://www.roblox.com/games/73453386951995) · [Creator Dashboard](https://create.roblox.com/dashboard/creations/experiences/10777817254/overview)

## Configure GitHub publishing

1. In Roblox Creator Dashboard, create an Open Cloud key scoped to Aether Isles with asset read/write and `universe.place:read`. Choose an expiry and network restrictions compatible with your Actions runner. [Roblox API keys](https://create.roblox.com/docs/cloud/auth/api-keys)
2. In the repository's **Settings → Environments**, open or create `roblox-production`. Set its deployment branch to `main` and add the key in the environment secret field named `ROBLOX_API_KEY`. The workflow already contains the destination IDs. [Repository environments](https://github.com/Matthew-Uhlar/RobloxMMO/settings/environments)
3. After the next gameplay merge or manual run, open **Publish Roblox place** in Actions. Its receipt records the source binary's hash, place ID and published Roblox revision. Open the game and verify a feature introduced in that revision. [Publish workflow](https://github.com/Matthew-Uhlar/RobloxMMO/actions/workflows/publish.yml)

## Enable original art uploads from Studio

In Aether Isles, open **Assistant Settings → MCP Permissions → Upload folders** and add the project's `art` directory to upload original meshes, textures and launch images. The asset read/write scopes were confirmed. The local folder check rejected the woven menu texture. Place icons and detail-page thumbnails use asset permissions. Homepage thumbnail personalization has its own permission. [Studio MCP permissions](https://create.roblox.com/docs/studio/mcp-open-cloud) · [Experience icons and thumbnails](https://create.roblox.com/docs/cloud/guides/experience-icons-and-thumbnails)

## Publish an update

**Publish Roblox place** is configured to deploy automatically when `main` changes root `.lua` files, `default.project.json`, or files under `art/` (excluding Markdown). Documentation-only changes outside those paths do not trigger deployment. Automatic deployment still requires the `roblox-production` environment and `ROBLOX_API_KEY`; a push alone is not a confirmed release.

The manual path remains **Actions > Publish Roblox place > Run workflow** on `main`, entering `73453386951995`. The workflow tests and builds that revision, retains its binary, validates the universe/place relation, uploads and polls the result. The Roblox key is supplied only to the publishing step. The normal build has no Roblox credential.

The publisher follows Roblox's current [place publishing guide source](https://github.com/Roblox/creator-docs/blob/main/content/en-us/cloud/guides/usage-place-publishing.md): Assets API multipart PATCH, `published=true`, `.rbxl` MIME `application/octet-stream`, then operation polling. Success requires the target asset, a revision ID and `isPublished=true`. The [Get Place endpoint](https://create.roblox.com/docs/cloud/reference/features/places) checks destination membership first. Some cached documentation still describes the older universe-version POST API; this script intentionally uses the current Assets guide.

For local validation without credentials or network:

```powershell
./scripts/publish.ps1 -UniverseId 10777817254 -PlaceId 73453386951995 -DryRun
```

For a real local upload, provide `ROBLOX_API_KEY` securely in the process environment, then omit `-DryRun`. The script uses neither browser cookies nor keys in command-line arguments.

Read requests retry transient HTTP 429/5xx/network errors up to four times. Upload writes are never automatically repeated after an ambiguous response, avoiding accidental duplicate versions. If polling times out, retain `publish-receipt.json` and resume with the same IDs/file plus `-OperationId OPERATION_ID`. The original matching receipt is required (use `-ReceiptPath` if downloaded elsewhere); mismatched target, operation or file hash is rejected. On an upload timeout before an operation is returned, inspect Creator Dashboard/version history before retrying. HTTP failures and operation errors fail the workflow, never mark it published. The receipt contains IDs/hash/version, not a secret.

## Required engine and release checks

- Start a real Studio client; check Output for errors and test travel, gathering, crafting, menus, combat and death.
- Test phone/tablet sizes and gamepad navigation, every sign, worker pad and companion. Test both mesh and wedge fallback rendering. Runtime generated meshes are not pre-authored EditableMesh instances in the uploaded place; confirm actual rendering. Roblox documents unsupported instance updates in its publishing guide; use Studio if such saved instance types are introduced.
- Use at least two clients for co-op invites, shared island membership/supplies/builds, resource ownership and combat rewards. Verify Ironman restrictions and permanent membership warnings.
- In a separate test universe, verify save/rejoin, offline output, market recovery and DataStore failure behavior. Studio API-service access is optional for Studio persistence testing; do not enable it against production data merely to preview. Real published servers use their normal server DataStores.
- Verify the published version in Studio/Creator Dashboard and join its Roblox start-place URL. Confirm rejoin preserves progress and the intended audience can access it.
- Upload the final icon/thumbnail, finish accurate content ratings and audience configuration. For rollback, rebuild a known-good source revision and publish it; restore place content without erasing DataStores. Existing live servers may need restarting through Roblox's release controls.

## Current deployment boundary

### Rolling market updates

Skyreach servers handle fixed-price listings. Updated servers can also buy and sell priced lots. For equally priced lots, fixed-price listings are filled first, then priced listings are filled in insertion order. A player who reserved coins or goods on an updated server can continue playing on Skyreach. Their reservation settles when they next join an updated server. Keep a compatible server available or settle outstanding reservations before rolling the entire fleet back to Skyreach.

All eight cloud scripts matched the **Skyreach** source at `975be9c`. Later Observatory, amount-based banking and priced-trade source has local builds/smoke evidence, but its deployment remains **unknown** until a receipt or Studio/version-history check proves otherwise. Studio displaying Public, ages 16+ is independent of which code version is deployed. Do not label an automatic trigger, CI artifact, candidate Studio window or local `.rbxl` as a completed upload.

The [original mesh GLB bundle](art/import/README.md) is prepared for a separate authorized import. Its 20 shapes have not been established as persistent uploaded Roblox templates. Keep the existing runtime fallback until imported assets are verified and integrated reproducibly.

## Verification limits

Local script parsing, offline dry-run validation, invalid-input rejection and YAML policy checks are automated. Tool installation, game tests/build, release checks and artifact upload succeeded in GitHub CI run `44492070676` for commit `975be9c88688def742f15a8b30d91b29c4824588`. Roblox HTTP publishing remains unverified until a valid API key is supplied and the separate publish workflow succeeds. This workflow does not claim the unfinished full game scope is complete.



## Can GitHub publish without a Roblox credential?

No supported GitHub workload-identity/OIDC trust exchange was found in the current official Roblox documentation. Roblox documents [API keys](https://create.roblox.com/docs/cloud/auth/api-keys) and [OAuth authorization-code/refresh-token flows](https://create.roblox.com/docs/cloud/auth/oauth2-reference). OAuth still requires a Roblox app registration, user authorization and tokens; Roblox's OpenID provider authenticates users and does not establish GitHub Actions workload trust. This is a documentation-based conclusion, not a claim that future support is impossible. The provided workflow therefore requires `ROBLOX_API_KEY`; GitHub's `GITHUB_TOKEN` or `id-token: write` alone does not provide documented Roblox publishing authorization.
