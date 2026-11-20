# Atlas & HUD screenshots

> **These are renders from an approximate layout emulator, not Roblox captures.**
> `tools/render-ui.luau` runs `ui.client.lua` and `combat.client.lua` headlessly
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
- `filter` — substring of `<Tab>-<Section>` (e.g. `Ledger`, `Hero-Gear`), `HUD` or `Builder`
  (the island builder controls, `build.client.lua`).
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

## Design system ("Aether Brass")

- **Surfaces** (dark → light): track `060E14` (wells, bar tracks) · deep `0C1820`
  (cards, tiles) · ink `12222C` (window) · slate `1E3946` (controls) · raised
  `2A4D5E` (selected/hover). Every plate gets a vertical sheen (UIGradient), a
  1px inner bevel highlight that fades downwards, and a rim stroke whose
  gradient lights the top edge.
- **Accents**: brass `C9974A` rims and ornaments, gold `F3C66E` headings and
  primary actions, mint `7FE3CC` state/selection, ember `EF7D67` danger/locked.
- **Ornament**: corner gems with L-bracket arms (rotated frames) on the atlas
  window, level-up banner, bank plate and boss panel; double rim on the window;
  ribbon tab on the level-up banner; fading brass hairline dividers.
- **Type scale**: display FredokaOne 22–28 (titles, banner) · heading Builder
  Sans ExtraBold 13–17 (card titles, section headings in gold caps) · label
  Builder Sans Bold 11–14 · body Builder Sans Medium 12–14. Floor 11px (12px on
  phones).
- **Spacing**: 4px grid; cards pad 14 (10 on phones), lists gap 8.
- **Components**: segmented section bars in a sunken well (gold = page section,
  mint = in-page filter); buttons with primary (gold) / secondary / danger /
  disabled tones, leading action glyphs, hover wash, press scale and a brass
  gamepad selection ring; pill status badges; rarity item plates with glow from
  Rare up and an "E" tag for equipped gear; gradient meters with gloss and a
  glowing end cap; tick-box checklists; depth-bar order book; two-card stat sheet.
- **Motion**: atlas opens with a slide + Back-eased scale and a shade fade; page
  and section switches slide content up 10px; toasts rise in; the level-up
  banner pops in.

## Index

All renders come from the redesigned UI unless prefixed `before-`.

| File | Size | What |
| --- | --- | --- |
| `desktop-Journal-Bearing.png` | 1366x768 | Numbered heading, next goal, route chart, guild contract with primary Claim |
| `desktop-Journal-Diaries.png` | 1366x768 | Diary tiers: tier pips, tick-box task checklists, progress meters |
| `desktop-Journal-Calendar.png` | 1366x768 | Skyward Calendar: season pips, day meter, countdowns, festivals |
| `desktop-Journal-Crew.png` | 1366x768 | Crew page: homestead level meter, roster, stores |
| `desktop-Hero-Skills.png` | 1366x768 | Skill tiles with level medallions, perks and gradient meters |
| `desktop-Satchel-Items.png` | 1366x768 | Rarity item plates with glow, stack counts, equipped tags |
| `desktop-Satchel-ItemDetail.png` | 1366x768 | Item detail card: Equip (primary), Enchant, Sell |
| `desktop-Workshop-Forge.png` | 1366x768 | Station card with skill meter, category filter, recipe cards |
| `desktop-Hunt-Slayer.png` | 1366x768 | Active contract (danger-toned Abandon), slayer lines, tier filter |
| `desktop-Ledger-Bank.png` | 1366x768 | Ornamented balance plate, amount well, presets, gold Transfer |
| `phone-Hero-Skills.png` | 844x390 | Side tab rail, skills grid |
| `phone-HUD.png` | 844x390 | HUD: guild badge, boss panel, banners, toast, action bar pills, attack button |
| `phone-Builder.png` | 844x390 | Island builder controls above the action bar |
| `compact-HUD.png` | 730x303 | Short-screen HUD: slim level-up banner clears the toast |
| `compact-Satchel-Items.png` | 730x303 | Rail layout, item grid |

Before / after (four key pages):

| Before | After | Change |
| --- | --- | --- |
| `before-desktop-Hero-Gear.png` | `after-desktop-Hero-Gear.png` | 3-column stat chips → two titled stat cards (Combat, Gathering & luck) with glyph chips and zebra rows; layered window, ornamental corners, crisp tab plates, segmented section well |
| `before-desktop-HUD.png` | `after-desktop-HUD.png` | Flat text action bar → health meter / XP pill (skill medallion + level meter) / defense pills; level-up banner with ribbon, medallion and ornaments; boss panel with level medallion, ember rim and corner gems; ribbon toast and event banner |
| `before-phone-Ledger-Orders.png` | `after-phone-Ledger-Orders.png` | Order book lines → depth-bar order book; rarity plates; pill badges; rail with selected tab glow |
| `before-desktop-Journal-Quests-full.png` | `after-desktop-Journal-Quests-full.png` | Inline ✓/✗ text → tick-box checklists with right-aligned counts, status pills, gold Claim |

Combat styles (bows, staves, spells):

| File | Size | Shows |
| --- | --- | --- |
| `combat-desktop-HUD.png` | 1366x768 | Mana pill beside health, spell bar (style chip with mana, autocast slot, greyed unaffordable slot, cost captions), CAST button |
| `combat-compact-HUD.png` | 730x303 | The same HUD on a short phone: spell bar left of the Attack button, toasts lifted above it |
| `desktop-Hero-Combat-full.png` | 1366x768 | Hero › Combat: style card with mana meter, quiver and arrows, combat levels, triangle explainer, switch-style weapons |
| `desktop-Hero-Spellbook.png` | 1366x768 | Hero › Spellbook: autocast summary, spell costs (staff-supplied glyphs free), damage estimate |
| `desktop-Hunt-Bestiary.png` | 1366x768 | Bestiary entries with attack style, weakness and resistance |

Agility & Hunter:

| File | Size | Shows |
| --- | --- | --- |
| `compact-HUD-Agility.png` | 730x303 | Lap tracker (course, obstacle 3/6, next obstacle, step countdown, obstacle pips, best lap) and trap counter in the left column, narrow so the toast clears them |
| `desktop-Journal-Agility.png` | 1366x768 | Journal › Agility: Skyrunner's log (lap milestones, Surefoot), course cards with obstacle chains, slip chance, lap-milestone pips, Guide |
| `desktop-Hunt-Hunter.png` | 1366x768 | Hunt › Hunter: Tracker's log, traps in the field, hunter log entries with log-tier pips, kit, catch chance and drops |
| `phone-Ledger-Vendors.png` | 844x390 | Ledger › Vendors: Skymark Exchange open with countdown, Skymark purse, stock with owned badges |
