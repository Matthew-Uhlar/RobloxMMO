# Publishing Aether Isles

A **new private** Aether Isles experience was created in Studio on November 19, 2026: universe `10777817254`, start place `73453386951995`. These verified IDs are already configured in the publish workflow; no GitHub destination variables are needed. A successful source build alone does not establish engine quality or a public release.

## One-time Roblox setup

1. The new destination already exists. Open [its Creator Dashboard](https://create.roblox.com/dashboard/creations/experiences/10777817254/overview) to configure metadata/access. Do not create another experience or replace a prior game.
2. Keep early access limited while running the checks below. The game page is [Aether Isles](https://www.roblox.com/games/73453386951995).
3. Complete the current account/audience requirements shown by Roblox: age check, account standing/age, and content questionnaire. Broader all-age availability has additional verification, 2FA, subscription-or-fee and evaluation requirements. Do not assume a binary upload makes the game public. Configure **Publish settings > Manage Audience** when ready. These settings and requirements can change; follow the current [official publishing guide](https://create.roblox.com/docs/production/publishing/publish-games-and-places).

Suggested description, based only on implemented content: “Explore floating islands, gather resources, craft equipment and grow your worker fleet. Build a homestead with friends and challenge the Hollow Observatory.”

## GitHub setup

1. **Completed:** source and workflows are on the default branch of [Matthew-Uhlar/RobloxMMO](https://github.com/Matthew-Uhlar/RobloxMMO). [CI run 44492070676](https://github.com/Matthew-Uhlar/RobloxMMO/actions/runs/44492070676) passed installation, tests/build, release validation and artifact upload.
2. In repository Settings > Environments, create `roblox-production`. Restrict its deployment branches to the default branch. Optional required reviewers provide a separate release checkpoint.
3. No destination variables are required; the workflow is bound to universe `10777817254` and place `73453386951995`.
4. Create an Open Cloud API key in Creator Dashboard with asset Read/Write for the target and `universe.place:read` for destination validation. Store it as the environment secret `ROBLOX_API_KEY`. Keep permissions limited to this destination. Use an expiry and network restrictions compatible with the chosen runner; dynamic GitHub-hosted IPs require an appropriate runner/network strategy. See [API keys](https://create.roblox.com/docs/cloud/auth/api-keys) and [GitHub environment secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets). Never paste credentials into this repository.
5. **Completed:** GitHub Actions builds successfully. Download artifact `Aether-Isles-975be9c88688def742f15a8b30d91b29c4824588` from the passing run above. It was independently confirmed present and unexpired through the GitHub connector (artifact ID `14512614347`, ZIP size 70,133 bytes). Subsequent pushes build new artifacts automatically.

## Publish an update

Run **Actions > Publish Roblox place > Run workflow** on the default branch and enter `73453386951995`. The workflow tests and builds that revision, retains its binary, validates the universe/place relation, uploads and polls the result. The Roblox key is supplied only to the publishing step. The normal build has no Roblox credential.

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

## Verification limits

Local script parsing, offline dry-run validation, invalid-input rejection and YAML policy checks are automated. Tool installation, game tests/build, release checks and artifact upload succeeded in GitHub CI run `44492070676` for commit `975be9c88688def742f15a8b30d91b29c4824588`. Roblox HTTP publishing remains unverified until a valid API key is supplied and the separate publish workflow succeeds. This workflow does not claim the unfinished full game scope is complete.



## Can GitHub publish without a Roblox credential?

No supported GitHub workload-identity/OIDC trust exchange was found in the current official Roblox documentation. Roblox documents [API keys](https://create.roblox.com/docs/cloud/auth/api-keys) and [OAuth authorization-code/refresh-token flows](https://create.roblox.com/docs/cloud/auth/oauth2-reference). OAuth still requires a Roblox app registration, user authorization and tokens; Roblox's OpenID provider authenticates users and does not establish GitHub Actions workload trust. This is a documentation-based conclusion, not a claim that future support is impossible. The provided workflow therefore requires `ROBLOX_API_KEY`; GitHub's `GITHUB_TOKEN` or `id-token: write` alone does not provide documented Roblox publishing authorization.
