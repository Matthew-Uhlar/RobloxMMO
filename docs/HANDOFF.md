# Handoff: Aether Isles (for the next lead)

Written 2026-11-21 by the previous lead session. Read this first, then `docs/DEPTH-CONTRACT.md` (the interface contract, §1–30) and `PROJECT-STATUS.md`.

## 1. What the owner wants

An original Roblox MMO, **Aether Isles**: floating sky islands with Hypixel SkyBlock and Old School RuneScape mechanics, and the same skill intricacy and depth of progression. Keep adding content and depth until it is on their level. The owner's standing feedback, most recent first:

- **Art direction:** modern and detailed, closer to Hypixel than OSRS. **Never low-poly or flat-shaded.** Rich colour, glow accents, bold outlined display text.
- **Map:** make the map (Sky Chart warp map and minimap) much more detailed, in that modern style.
- **Fixed by the merge in §4, needs a check in Studio:** grass texture was clipping into the island rock.
- **Gameplay and UI:** weapons, picks and tools must be held in hand with physical swing animations. The inventory must be easy to reach. The UI should work like OSRS or SkyBlock and be fully overhauled. Player islands must be much larger. All signs must be appealing and detailed. Custom meshes everywhere (bridges, islands, signs) must be more detailed. Places need unique Aether Isles names, with quest-giving NPCs and basic MMO mechanics.
- **Earlier feedback:** islands too small, lighting buggy, signs and graphics need custom meshes, menus need an overhaul, every gather or interact needs swing and interact animations.
- **Originality:** all names, art and branding must be original. Use the wikis and videos for mechanics and feel only.
- **Reference material:**
  - `https://hypixelskyblock.minecraft.wiki/`
  - `https://oldschool.runescape.wiki/`
  - the owner's three videos, already studied; notes are in `docs/reference-notes/` (see §6)
  - the owner's screenshots, described in the reference notes

## 2. Repository, branch, PR, publishing

- **Repo:** `Matthew-Uhlar/RobloxMMO`.
- **Working branch:** `claude/pensive-maxwell-145p0c`. Commit and push only here.
- **Open PR:** [Matthew-Uhlar/RobloxMMO#5](https://github.com/Matthew-Uhlar/RobloxMMO/pull/5) (branch → `main`). It holds every wave since the first publish.
- **Do not merge it without the owner's explicit say-so.** Approval for the earlier PR #4 does not carry over.
- **Publishing:** merging to `main` triggers `.github/workflows/publish.yml`, "Publish Roblox place", which uses environment `roblox-production` and secret `ROBLOX_API_KEY` (universe 10777817254, place 73453386951995). The owner has published once (PR #4). After any publish, check the run and ask the owner to play-test.
- **CI:** "Build and verify", `.github/workflows/build.yml`, runs `build.ps1` on Windows.
  - `.gitattributes` forces LF line endings, because suites slice other suites' source by markers containing `"\n"`.
  - Keep that rule. CRLF checkouts broke CI once.
- **Commit trailer** (every commit):
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01FkUNqZEFYap7XtGbpVDhXd
  ```
  (Use your own session's attribution lines if your environment gives different ones.)

## 3. Build and test

```bash
export PATH=$HOME/.cargo/bin:$PATH   # Lune 0.11.1, Rojo 7.7.1 (cargo install ... --locked if missing)
./scripts/build.sh
```

- Runs `node art/import/verify-import.cjs`, then **30 Lune suites** (`verify-*.luau`), then `rojo build` → `Aether-Isles.rbxl` and `verify.luau`, which compiles and checks the scripts.
- Every suite must print `SUITE-END <file>`. Lune exits 0 on a coroutine that yields forever, so the build fails if any suite is missing its sentinel.
- `build.ps1` mirrors the suite list. **Add every new suite to both files.**
- **Generated art:** after editing `art/*-shapes.cjs`, run `node art/generate-props.cjs && node art/generate-import.cjs`. On merge conflicts in `art/import/*.glb` or `manifest.json`, regenerate instead of hand-merging.
- **Static world part budget:** 4000, about 3,485 used. Detailed shapes are forged on the client as EditableMeshes (`forge.client.lua`), so a `meshSlot` proxy costs one server part.

## 4. How the work is organised

- **The lead** owns the contract, `shared/GameData.lua` structure and `shared/Progression.lua`, and makes balance decisions.
- **Teams** are agents run with `isolation: "worktree"`, one feature each, with a precise brief: files, contract section, tests, a SUITE-END suite, docs. Each starts with `git merge --no-edit claude/pensive-maxwell-145p0c`.
- **Merging:**
  - `git merge --no-edit worktree-agent-<id>`.
  - **Conflict rule:** keep both sides.
    - In `GameData.lua`, team sections are appended just before `return Data`. Insert the section; never concatenate mid-function.
    - In the build script lists, take the union.
    - In the contract, keep the newer text and drop stale duplicates.
  - Then run a full build, commit and push.
- **Quality control:** an independent read-only review (`roblox-dev:roblox-reviewer`) runs after every merge, then a fix team handles all findings with a regression test per fix. Lead decisions are written into the fix brief and into the contract.
- **Recurring rules from past reviews** (check every new feature against these):
  - **No coin mints.** Every shop offer must have price per unit ≥ sell value × 1.3, and crafted item value ≤ input value.
  - **Shop purchases** go straight to `p.items`, never through `collect()`.
  - **Server-authoritative** verbs, validated and rate-limited, routed through `IsleAction` and `perform`.
  - **Rejoin-safe** and lease-safe saves. Every server teleport sets `FastTravelAt`.
  - **Day boards roll forward only** (guards against servers whose clocks are behind).
  - **`perkStats` stays within `Data.PerkBudget`** (300 Health / 125 Defense).
  - **Upgraded last copies** can't be sold, dropped or donated.
  - **Rewards go only to members present** who contributed, with idle and AFK removal.
- **Usage limits:** when teams stop with "hit your 5-hour limit", resume each with `SendMessage` after the reset. Don't start duplicate agents.

## 5. State at handoff

**Merged and pushed** (head `19197da`; all 30 suites pass). Contract sections:

| § | Systems |
|---|---|
| 11–19 | gear depth, mastery and garden, endgame, workers, pets, dungeon classes, prayer and thieving, treasure trails, slayer tasks |
| 20–25 | commissions, collection log and museum; minigames; crafting; dungeon endgame; exploration and factions; lair bosses |
| 26 | held items, hotbar and swings |
| 27 | big home islands |
| 28 | shared sign system |
| 29 | "Skyforge" UI: `shared/UiTheme.lua`, `hud.client.lua` satchel, gear and Sky Chart, sidebar, action bar, Menu grid |
| 30 | world art and regions: forged hulls and bridges, landmarks, 27 NPCs, 23 regional quests, warp scrolls |

- Since §30 was written, a grass-clipping fix landed in `island()` in `world.server.lua`: the foundation and cliff now sit below the meadow slab, and verify-world asserts this.

**In flight.** Three teams were resumed after a usage-limit stop. Each works in a worktree branch `worktree-agent-<id>`; merge it when the team reports, or check with `git log claude/pensive-maxwell-145p0c..worktree-agent-<id>`.

| Team | Branch suffix | Scope |
|---|---|---|
| UI overhaul fixes | `a50ac0cc002df3d2d` | Satchel drag and click bugs, M opens the Sky Chart, Tab disables the core player list, minimap setting, world-boss board relayout, XP-drop lane, tablet docking, short windows, sell/drop guard for upgraded last copies, plus 12 lows. Was finishing §29 docs. |
| MMO feature gap | `a76e7974ed3e4bf31` | Account-level renown, onboarding objective chain into the sidebar, "COLLECTION UNLOCKED" and level-up toasts, shop quantity picker, launch vents, Magical Power stat-template NPC. Was writing `verify-features.luau` (§31). |
| Sky Chart map art | `a03113a93bebbd229` | 3D ViewportFrame warp map from the real island models (Hypixel-style), a more detailed minimap, §32. |

When each lands: merge, build, push, run a QC review, then a fix team.

**Known open items and ideas:**
- **Hollowcrown Edge** (lair unique) is now weaker than an easier crafted sword after the 85% rival cap. Give it a niche, such as a special ability. See §25.
- **StreamingEnabled is off.** Enabling it needs an audit of client scripts that read far-away world children (nav, motes, regions, ui). See §27.
- **Stale display names** remain in `shared/GameData.lua`: "Aether Hub" and "Quarry Cay" in the base regions, tutorial and recall text.
- **Gaps from the OSRS videos still unbuilt:**
  - a "verb + target" action label;
  - a per-skill unlock guide in the skills panel;
  - a built-in quest helper;
  - a goal board;
  - market price history;
  - "closest teleport" on the map;
  - an optional HD lighting setting (Future lighting by default, with a performance setting);
  - built-in calculators;
  - OSRS-style hitsplats and overhead HP bars if missing;
  - chat filter tabs.
- **Everything visual still needs a Studio play-test:** held-item grips and swings, sign fonts and readability, hull and bridge proportions, the UI with the real Roblox fonts, phone performance.

## 6. Reference notes

`docs/reference-notes/` holds the owner's three videos, studied frame by frame, plus Gemini's narration-aware notes for part of the SkyBlock video:

- `skyblock-beginner-guide.md`: HUD, sidebar, tooltip format, menus, systems and world layout. Prioritised feature list at the end.
- `skyblock-beginner-guide-gemini.md`: Gemini notes on the first 10 minutes, which include narration.
- `osrs-starter-guide.md` and `osrs-complete-guide.md`: interface, systems and progression. Prioritised lists at the end.

Ignore any low-poly or flat-shaded recommendation in these notes (owner direction).

Gemini video access (the `watch` skill) uses a free-tier key with 20 requests a day.
- The previous session scheduled a resume of the segmented YouTube pass at 08:10 UTC on 2026-11-21. Its scratchpad script and notes live in the old session's `/tmp` scratchpad and may not exist in a new environment.
- YouTube blocks direct downloads from the cloud container. The owner shared the downloaded videos through a Google Drive folder instead.

## 7. Talking to the owner

- Reply in plain language: what changed, what's verified, what needs a play-test.
- Ask before merging or publishing the PR.
- Never echo secrets. The owner pasted a Gemini key in chat earlier, and it is stored only in `~/.config/watch/.env` in the old container.
