# Atlas & HUD screenshots

> **These are renders from an approximate layout emulator, not Roblox captures.**
> `tools/render-ui.luau` runs `ui.client.lua`, `combat.client.lua`, `hud.client.lua`
> and `nav.client.lua` headlessly
> against a mock instance tree with a mid-game snapshot, and
> `tools/rasterize-ui.py` lays the resulting GUI tree out with a re-implementation
> of the parts of Roblox's layout model the atlas uses, then draws it with Pillow.
> Fonts, glyph metrics, gradients and 3D thumbnails are approximations; the world
> behind the GUI is a flat placeholder backdrop. Use these to catch overlap,
> clipping, truncation, spacing and contrast problems, and confirm in Studio.

## Regenerating

From the project directory (Lune and Python 3 with Pillow required):

```sh
lune run tools/render-ui.luau [outDir] [filter] [--full] [--issues] [--sizes=1366x768,730x303]
```

- `outDir` — where PNGs go (default `build/screenshots`, untracked; do not commit
  bulk output — curate into this folder). One subfolder per size:
  `desktop` (1366x768), `phone` (844x390), `compact` (730x303).
- `filter` — substring of `<Tab>-<Section>` (e.g. `Ledger`, `Hero-Gear`, `Menu`), `HUD`
  (`HUD-Satchel`, `HUD-ContextMenu`, `HUD-Gear`), `WarpMap` or `Builder` (the island
  builder controls, `build.client.lua`).
- `--full` — also write `<page>-full.png`, the atlas ScrollingFrame unrolled to
  its whole canvas height (the normal PNG shows only what fits on screen).
- `--issues` — print automated findings: text under 11 px, truncated
  (`TextTruncate`) labels, and wrapped text overflowing its box.

Screen size is treated as the ScreenGui's AbsoluteSize (no top-bar inset). A full
render of all 34 shots × 3 sizes (Calendar and a sample crew included) takes
about half a minute.

## Emulator fidelity

Implemented: UDim2 Position/Size + AnchorPoint; UIListLayout (direction, padding,
LayoutOrder/Name sort, alignments); UIGridLayout (CellSize/CellPadding,
FillDirectionMaxCells); UIPadding (content and children); UISizeConstraint;
UIAspectRatioConstraint; UITextSizeConstraint; AutomaticSize X/Y (frames and
text); ScrollingFrame canvas, AutomaticCanvasSize, scroll bar and clipping;
ClipsDescendants; Visible; ZIndex with Sibling ordering and ScreenGui
DisplayOrder; BackgroundTransparency; UICorner; UIStroke including
Contextual-vs-Border semantics; UIGradient colour + transparency with Rotation on
fills, on **strokes** (gradient rims) and on **text** (per-pixel across the text
box); Rotation (drawn, not laid out); TextLabel/TextButton/TextBox with RichText
(`font color/size`, `b`, `br`), TextWrapped, TextScaled, TextTruncate,
TextStroke, placeholders; ViewportFrame thumbnails as a flat perspective
projection of the `art/PropCatalog.lua` shape (tint applied).

Fonts: Builder Sans (Medium/Bold/ExtraBold) is drawn with Inter at the matching
weight, FredokaOne with the vendored OFL `tools/fonts/FredokaOne-Regular.ttf`,
legacy Gotham/Antique with DejaVu. Glyphs a face lacks (✓ ✗ ❤ ❈ ☘ ⚔ …) fall back to
DejaVu per character, as Roblox falls back to its symbol fonts. Metrics still
differ from Roblox by a few percent.

Tweens: the harness applies every `TweenService:Create(...):Play()` goal at
once, so renders show the settled state of open/slide/pop-in transitions.

Not modelled: UIScale (renders at rest scale 1), CanvasGroup, images/textures,
UIListLayout wrapping/flex, rotated children, top-bar inset, gamepad selection
rings.

## Design system ("Skyforge", UI overhaul — docs/DEPTH-CONTRACT.md §29)

All tokens and components live in `shared/UiTheme.lua` (`ReplicatedStorage.AetherUiTheme`).

- **Surfaces** (dark → light): void `05080C` (tracks, wells) · inset `0B1017` (slots,
  cards) · panel `111822` (windows, sidebar) · raised `223042` (controls) · hover `2E4058`.
  Panels are translucent with a top-lit sheen.
- **Frames**: bronze `8A6A3B` rims lit to `F0CE82` at the top, an inner hairline, and
  four gold corner studs with bracket arms ("9-slice" built from frames, no images).
- **Accents**: gold `F7C548` headings and primary actions, mint `6FE3C8` state,
  ember `FF6B5A` danger/locked; bars health `FF4F4F`, defense `57D96A`, mana `4FA8FF`.
- **Rarity tiers**: Common `FFFFFF`, Uncommon `55FF55`, Rare `6E7BFF`, Epic `C04CFF`,
  Legendary `FFAA00`, Mythic `FF55FF` (+ reserved Divine / Special): slot borders,
  tooltip names and footers.
- **Type**: pixel display face (Roblox Arcade = Press Start 2P, vendored OFL in
  `tools/fonts`) for titles, section heads, stack counts and XP drops; Builder Sans
  ExtraBold / Bold / Medium for everything read. Floor 11 px (12 on phones).
- **Components**: item slot (pictogram, rarity border, count, equipped tag, cooldown
  sweep), lore tooltip, buttons (primary / secondary / danger / selected / ghost),
  tabs, bars, ornate frames; original item pictograms drawn from frames.
- **HUD lanes** (`Theme.hudLayout`): minimap top-left, sidebar top-right, a 9-slot
  hotbar gap bottom-centre with the action bar in the band above it, left/right
  columns for trackers and party/minigame/lair HUDs, a top lane for target panels.

The hotbar in these renders is a **stand-in** drawn with Theme slots where
`hotbar.client.lua` (Held Items team, not in this branch) places its bar.

## Index

| File | Size | What |
| --- | --- | --- |
| `desktop-HUD.png` | 1366x768 | Minimap with region + coordinates, isle sidebar (date, time, region, purse, Skymarks, objective, crew, dock), boss panel, level-up banner, OSRS XP drops + skill toast, action bar over the hotbar, spell bar + Attack |
| `phone-HUD.png` / `compact-HUD.png` | 844x390 / 730x303 | The same HUD on phones: 44 px minimap column, folded sidebar, spell bar centred in the hotbar band |
| `desktop-HUD-Satchel.png` | 1366x768 | Docked satchel (7 × 4, bag pages, search, sort, equipped tags) with a lore tooltip |
| `phone-HUD-Satchel.png` / `compact-HUD-Satchel.png` | 844x390 / 730x303 | Satchel modal (7 × 4; 14 × 2 on 303 px screens), 44 px controls |
| `desktop-HUD-ContextMenu.png` | 1366x768 | Right-click menu: Wield / Move to hotbar / Examine / Sell / Drop |
| `desktop-HUD-Gear.png` / `phone-HUD-Gear.png` | 1366x768 / 844x390 | Paperdoll (bag · head · pet / weapon · body · quiver / legs / feet) beside the stat sheet |
| `desktop-WarpMap.png` / `phone-WarpMap.png` / `compact-WarpMap.png` | all | Sky Chart: illustrated isles, warp points, padlocks with requirements, "you are here" |
| `desktop-Menu-Home.png` / `phone-Menu-Home.png` / `compact-Menu-Home.png` | all | Main menu grid (12 icon tiles with live captions) |
| `desktop-Menu-Settings.png` | 1366x768 | HUD preferences (pin satchel, XP drops, minimap) and keys |
| `desktop-HUD-Dungeon.png` | 1366x768 | Observatory party HUD in the right column under the sidebar |
| `compact-HUD-Agility.png` | 730x303 | Lap tracker and trap counter in the left column, clear of the hotbar |
| `desktop-Journal-Bearing.png` | 1366x768 | Re-skinned page: pixel section heads, bronze frames |
| `desktop-Journal-Diaries.png`, `desktop-Journal-Calendar.png`, `desktop-Journal-Crew.png`, `desktop-Journal-Agility.png` | 1366x768 | Journal pages in the new theme |
| `desktop-Hero-Skills.png`, `desktop-Hero-Combat-full.png`, `desktop-Hero-Spellbook.png` | 1366x768 | Hero pages |
| `desktop-Satchel-Items.png`, `desktop-Satchel-ItemDetail.png`, `compact-Satchel-Items.png` | | Atlas Satchel › Items (kept alongside the HUD satchel) |
| `desktop-Workshop-Forge.png`, `desktop-Hunt-Slayer.png`, `desktop-Hunt-Bestiary.png`, `desktop-Hunt-Hunter.png`, `desktop-Ledger-Bank.png` | 1366x768 | Workshop, Hunt and Ledger pages |
| `phone-Hero-Skills.png`, `phone-Ledger-Vendors.png`, `phone-Builder.png` | 844x390 | Phone rail layout, vendors, island builder (the action bar steps aside) |

Before / after (the previous "Aether Brass" design → Skyforge):

| Before | After |
| --- | --- |
| `before-desktop-HUD.png` | `after-desktop-HUD.png` |
| `before-desktop-Hero-Gear.png` | `after-desktop-Hero-Gear.png` |
| `before-phone-Ledger-Orders.png` | `after-phone-Ledger-Orders.png` |
| `before-desktop-Journal-Quests-full.png` | `after-desktop-Journal-Quests-full.png` |

## Sign previews (`signs-*.png`)

Approximate offline renders of the §28 sign system (DEPTH-CONTRACT §28), not
Roblox captures. `tools/dump-signs.luau` builds the real world headlessly and
dumps chosen sign models (parts, mesh slots, declared boxes, SurfaceGui trees);
`tools/render-signs.py` lays the OBJ masters out the way `forge.client.lua` does
and perspective-warps the painted faces onto the boards:

```sh
lune run tools/dump-signs.luau build/signs.json "Artisans' Row" "Starforge" "Sky Harbor"
python3 tools/render-signs.py build/signs.json docs/screenshots/signs-archetypes.png [--night]
```

Fonts are stand-ins (DejaVu Serif Bold for Merriweather/Fondamento, Inter Bold
for BuilderSans) and wider than Roblox's, so a label may wrap here that fits in
one line in Studio. `--night` darkens the scene and keeps the faces ~80% lit
(LightInfluence 0.25). Confirm materials, fonts and night glow in Studio.
