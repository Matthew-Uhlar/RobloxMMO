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
- `filter` — substring of `<Tab>-<Section>` (e.g. `Ledger`, `Hero-Gear`) or `HUD`.
- `--full` — also write `<page>-full.png`, the atlas ScrollingFrame unrolled to
  its whole canvas height (the normal PNG shows only what fits on screen).
- `--issues` — print automated findings: text under 11 px, truncated
  (`TextTruncate`) labels, and wrapped text overflowing its box.

Screen size is treated as the ScreenGui's AbsoluteSize (no top-bar inset). A full
render of all 30 shots × 3 sizes takes about a minute.

## Emulator fidelity

Implemented: UDim2 Position/Size + AnchorPoint; UIListLayout (direction, padding,
LayoutOrder/Name sort, alignments); UIGridLayout (CellSize/CellPadding,
FillDirectionMaxCells); UIPadding; UISizeConstraint; UIAspectRatioConstraint;
UITextSizeConstraint; AutomaticSize X/Y (frames and text); ScrollingFrame canvas,
AutomaticCanvasSize, scroll bar and clipping; ClipsDescendants; Visible; ZIndex
with Sibling ordering and ScreenGui DisplayOrder; BackgroundTransparency;
UICorner; UIStroke including Contextual-vs-Border semantics; UIGradient
(approximate); Rotation (drawn, not laid out); TextLabel/TextButton/TextBox with
RichText (`font color/size`, `b`, `br`), TextWrapped, TextScaled, TextTruncate,
TextStroke, placeholders; ViewportFrame thumbnails as a flat perspective
projection of the `art/PropCatalog.lua` shape (tint applied).

Not modelled: Roblox fonts (DejaVu Sans / Sans Bold / Serif Bold stand in for
Gotham / GothamBold / Antique, so widths differ by a few percent), glyph
fallback (e.g. `⸕` Mining Speed shows as a box), UIScale, tweens, CanvasGroup,
images/textures, UIListLayout wrapping/flex, rotated children, top-bar inset.

## Index

Current renders:

| File | Size | What |
| --- | --- | --- |
| `desktop-Journal-Bearing.png` | 1366x768 | Journal → Bearing: next goal, route chart, contract |
| `desktop-Journal-Quests.png` | 1366x768 | Quest log (grouped Requires / Tasks / Rewards) |
| `desktop-Hero-Skills.png` | 1366x768 | Skill grid with skill-coloured rims |
| `desktop-Hero-Gear.png` | 1366x768 | Stat sheet, set bonus, equipment |
| `desktop-Satchel-Items.png` | 1366x768 | Item grid with rarity rims |
| `desktop-Workshop-Forge.png` | 1366x768 | Forge recipes |
| `desktop-Hunt-Slayer.png` | 1366x768 | Active slayer contract and lines |
| `desktop-Ledger-Orders.png` | 1366x768 | Bazaar order book and order placement |
| `desktop-HUD.png` | 1366x768 | HUD: boss panel, combat banner, level-up banner, toast, action bar |
| `phone-Hero-Skills.png` | 844x390 | Rail layout, skills |
| `phone-Ledger-Auctions.png` | 844x390 | Auction House |
| `phone-HUD.png` | 844x390 | HUD with touch attack button |
| `compact-Journal-Diaries.png` | 730x303 | Achievement diary |
| `compact-Hero-Gear-full.png` | 730x303 | Whole Gear page unrolled |
| `compact-Ledger-Bank.png` | 730x303 | Bank (formatted balances) |

Before / after (the three most improved pages):

| Before | After | Change |
| --- | --- | --- |
| `before-compact-HUD.png` | `after-compact-HUD.png` | Level-up banner covered the HUD badge and boss panel; toast sat under the attack button; bar track invisible |
| `before-desktop-Journal-Quests-full.png` | `after-desktop-Journal-Quests-full.png` | Inline "Requires/Tasks/Rewards" prefixes replaced by gold group captions + indented checklists; button text no longer outlined |
| `before-compact-Satchel-Collections-full.png` | `after-compact-Satchel-Collections-full.png` | Column of identical "???" cards replaced by one grid of sealed tiles |
