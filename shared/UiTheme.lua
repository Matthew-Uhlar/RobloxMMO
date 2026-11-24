--!nocheck
-- Aether Isles UI theme ("Skyforge"): one shared visual language for every
-- client script (atlas, HUD, satchel, hotbar, Wayfinder, combat HUD).
-- ReplicatedStorage.AetherUiTheme. See docs/DEPTH-CONTRACT.md §29.
--
--   Tokens     Theme.hex / Theme.color (palette), Theme.font, Theme.text (type
--              scale), Theme.space, Theme.rarity(rarity) → {hex, color, rank}
--   Components Theme.frame (ornate 9-slice panel), Theme.slot / Theme.setSlot
--              (item slot: icon + rarity border + stack count + cooldown sweep),
--              Theme.icon (§52 procedural vector item icon, cached), Theme.tooltip /
--              Theme.showTooltip (item lore card), Theme.button / Theme.tone,
--              Theme.tabs / Theme.selectTab, Theme.bar / Theme.setBar
--   Pure       Theme.lore(def, ctx) (tooltip lines), Theme.itemActions(def, ctx)
--              (context menu → server verbs), Theme.hudLayout(w, h, opts) (HUD
--              lanes, incl. the bottom-centre hotbar gap), Theme.hotbarStyle()
--              (STYLE table for hotbar.client.lua), Theme.isleClock(t, Data),
--              Theme.WorldMap (warp map tiles), Theme.sortItems, Theme.MapArt (§32)
-- Everything here builds from Frames, UIStroke, UIGradient and UICorner (no
-- uploaded images), so it renders identically in Studio and in the headless
-- emulator (tools/render-ui.luau). Builders never allocate per frame: callers
-- pool slots and rows and only call Theme.setSlot / Theme.setBar on change.
local Theme = {}
Theme.VERSION = 1

local function rgb(hex) return Color3.fromHex(hex) end
Theme.rgb = rgb

------------------------------------------------------------------------------
-- Tokens
------------------------------------------------------------------------------
-- Surfaces darkest → lightest: void (wells, bar tracks) < inset (slots, cards)
-- < panel (window body) < raised (controls) < hover. Bronze frames with a gold
-- top light; gold = headings / primary, mint = state / selection, ember =
-- danger / locked.
Theme.hex = {
	void = "05080C", inset = "0B1017", panel = "111822", panelTop = "1A2431", raised = "223042", hover = "2E4058",
	line = "2B3A4C", frame = "8A6A3B", frameHi = "F0CE82", frameLo = "3E2C15",
	gold = "F7C548", goldSoft = "FFE6A6", text = "F3EEE2", dim = "A9B4C0", faint = "8592A0", -- faint ≥ 4.5:1 on void / inset / panel / panelTop
	mint = "6FE3C8", ember = "FF6B5A", health = "FF4F4F", defense = "57D96A", mana = "4FA8FF", xp = "8EE05A",
	onGold = "2A1A04", prompt = "FFFF55", -- prompt: SkyBlock's yellow click line (tooltip footer, §34)
}
Theme.color = {}
for name, hex in pairs(Theme.hex) do Theme.color[name] = rgb(hex) end
Theme.color.white, Theme.color.black = Color3.new(1, 1, 1), Color3.new(0, 0, 0)

-- Rarity tiers (Data.Rarity: Common → Mythic) plus two reserved display tiers.
Theme.RarityOrder = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Divine", "Special"}
Theme.Rarities = {
	Common = {hex = "FFFFFF", frame = "9AA3AE", rank = 1}, Uncommon = {hex = "55FF55", frame = "4FCB4F", rank = 2},
	Rare = {hex = "6E7BFF", frame = "5562F0", rank = 3}, Epic = {hex = "C04CFF", frame = "A23ED8", rank = 4},
	Legendary = {hex = "FFAA00", frame = "F0A01A", rank = 5}, Mythic = {hex = "FF55FF", frame = "E04CE0", rank = 6},
	Divine = {hex = "55FFFF", frame = "3FD8E0", rank = 7}, Special = {hex = "FF5555", frame = "E04848", rank = 8},
}
function Theme.rarity(name)
	local r = Theme.Rarities[name] or Theme.Rarities.Common
	if not r.color then r.color, r.frameColor = rgb(r.hex), rgb(r.frame) end
	return r
end

-- Type: a pixel display face for headings, counters and stack counts (Roblox
-- "Arcade" = Press Start 2P), Builder Sans for everything people read.
Theme.font = {
	display = Enum.Font.Arcade, title = Enum.Font.Arcade, heading = Enum.Font.BuilderSansExtraBold,
	label = Enum.Font.BuilderSansBold, body = Enum.Font.BuilderSansMedium, number = Enum.Font.Arcade,
}
-- Sizes in px; `small` is the floor on desktop, `compactFloor` on phones.
Theme.text = {hero = 22, title = 16, display = 12, heading = 15, label = 13, body = 13, small = 11, micro = 10, compactFloor = 12}
Theme.space = {xs = 4, s = 8, m = 12, l = 16, xl = 24, radius = 6, touch = 44}

------------------------------------------------------------------------------
-- Builders
------------------------------------------------------------------------------
local function make(class, parent, props)
	local object = Instance.new(class)
	if class == "UIStroke" then object.ApplyStrokeMode = Enum.ApplyStrokeMode.Border end
	for key, value in pairs(props or {}) do object[key] = value end
	object.Parent = parent
	return object
end
Theme.make = make
local C = Theme.color

-- Vertical light: the fill is multiplied from `top` to `bottom`.
function Theme.sheen(object, top, bottom)
	top, bottom = top or 1, bottom or 0.72
	return make("UIGradient", object, {Name = "Sheen", Rotation = 90, Color = ColorSequence.new(Color3.new(top, top, top), Color3.new(bottom, bottom, bottom))})
end
-- Bronze frame stroke lit from the top edge.
function Theme.rim(object, thickness, hi, lo, transparency)
	local stroke = make("UIStroke", object, {Name = "Rim", Color = C.white, Thickness = thickness or 2, Transparency = transparency or 0})
	make("UIGradient", stroke, {Rotation = 90, Color = ColorSequence.new(hi or C.frameHi, lo or C.frameLo)})
	return stroke
end
function Theme.corner(object, radius)
	return make("UICorner", object, {CornerRadius = UDim.new(0, radius or Theme.space.radius)})
end
-- Ornate corners: a gold stud on each corner with bracket arms along both edges.
function Theme.ornaments(object, size, inset, color)
	size, inset, color = size or 6, inset or 4, color or C.frameHi
	local holder = make("Frame", object, {Name = "Ornaments", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Active = false, ZIndex = 3})
	local arm = math.floor(size * 2.6)
	for _, c in ipairs({{0, 0}, {1, 0}, {0, 1}, {1, 1}}) do
		local sx, sy = if c[1] == 0 then 1 else -1, if c[2] == 0 then 1 else -1
		make("Frame", holder, {Name = "ArmX", AnchorPoint = Vector2.new(c[1], 0.5), Position = UDim2.new(c[1], sx * (inset + size * 0.5), c[2], sy * inset),
			Size = UDim2.fromOffset(arm, 2), BackgroundColor3 = color, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 3})
		make("Frame", holder, {Name = "ArmY", AnchorPoint = Vector2.new(0.5, c[2]), Position = UDim2.new(c[1], sx * inset, c[2], sy * (inset + size * 0.5)),
			Size = UDim2.fromOffset(2, arm), BackgroundColor3 = color, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 3})
		local stud = make("Frame", holder, {Name = "Stud", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(c[1], sx * inset, c[2], sy * inset),
			Size = UDim2.fromOffset(size, size), Rotation = 45, BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 4})
		make("UIStroke", stud, {Color = C.frameLo, Thickness = 1})
	end
	return holder
end
-- Hairline divider fading out at both ends.
function Theme.rule(parent, y, color, inset)
	local line = make("Frame", parent, {Name = "Rule", BackgroundColor3 = color or C.frame, BorderSizePixel = 0, Position = UDim2.new(0, inset or 0, 0, y or 0),
		Size = UDim2.new(1, -2 * (inset or 0), 0, 1), Active = false})
	make("UIGradient", line, {Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.15),
		NumberSequenceKeypoint.new(0.85, 0.15), NumberSequenceKeypoint.new(1, 1)})})
	return line
end
function Theme.label(parent, props)
	local base = {BackgroundTransparency = 1, Font = Theme.font.body, TextSize = Theme.text.body, TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd}
	for k, v in pairs(props or {}) do base[k] = v end
	return make("TextLabel", parent, base)
end

-- Ornate panel ("9-slice" from code): translucent body with a top-lit sheen,
-- double bronze frame, corner studs and an optional title band. opts: name,
-- position, size, anchor, transparency, title, titleSize, ornate (default true),
-- header (px, default 28 with a title). Returns frame, body.
function Theme.frame(parent, opts)
	opts = opts or {}
	local frame = make("Frame", parent, {Name = opts.name or "Panel", Position = opts.position or UDim2.new(), Size = opts.size or UDim2.fromScale(1, 1),
		AnchorPoint = opts.anchor or Vector2.zero, BackgroundColor3 = opts.color or C.panel, BackgroundTransparency = opts.transparency or 0.08,
		BorderSizePixel = 0, Visible = opts.visible ~= false, ZIndex = opts.zIndex or 1})
	Theme.corner(frame, opts.radius or Theme.space.radius)
	make("UIGradient", frame, {Name = "Sheen", Rotation = 90, Color = ColorSequence.new(rgb("D8DEE8"), rgb("8A93A0"))})
	Theme.rim(frame, opts.rimThickness or 2)
	local inner = make("Frame", frame, {Name = "InnerRim", BackgroundTransparency = 1, Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6), Active = false})
	Theme.corner(inner, math.max(0, (opts.radius or Theme.space.radius) - 2))
	make("UIStroke", inner, {Color = C.frameHi, Thickness = 1, Transparency = 0.78})
	if opts.ornate ~= false then Theme.ornaments(frame, opts.studSize or 6, 4) end
	local headerHeight = opts.header or (if opts.title then 28 else 0)
	if opts.title then
		local band = make("Frame", frame, {Name = "Header", BackgroundColor3 = C.void, BackgroundTransparency = 0.45, BorderSizePixel = 0,
			Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 0, headerHeight - 3)})
		Theme.corner(band, 4)
		Theme.label(band, {Name = "Title", Text = opts.title, Font = Theme.font.display, TextSize = opts.titleSize or Theme.text.display, TextColor3 = C.gold,
			Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), TextStrokeTransparency = 0.4, TextStrokeColor3 = C.void,
			TextXAlignment = opts.titleAlign or Enum.TextXAlignment.Left})
		Theme.rule(frame, headerHeight, C.frame, 10).Name = "HeaderRule"
	end
	local body = make("Frame", frame, {Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, headerHeight), Size = UDim2.new(1, 0, 1, -headerHeight)})
	return frame, body
end

------------------------------------------------------------------------------
-- §52 item icons: procedural vector icons (Skyforge "Icon Atlas"). Every item
-- resolves, by data alone (kind → category → skill / slot / tool / held class →
-- id keywords → the kind's own default), to one of the FAMILY motifs below: a
-- short list of layered shapes (sticks, boxes, discs) in named tones derived
-- from the item's colour, each lit from the top-left by a three-stop
-- UIGradient (the light stays put however the layer is turned), with a dark
-- outline and a soft gleam. Gear wears a rarity corner gem; Rare and above sit
-- on a rarity halo (Data.Rarity hues via Theme.Rarities); Condensed / Radiant
-- materials stack on a compressed block (Radiant adds a glow and a spark).
-- Built icons are cached as unparented templates (LRU, Theme.IconCache) and
-- cloned, so a satchel refresh never rebuilds the same icon twice.
------------------------------------------------------------------------------
local function lighten(color, amount) return color:Lerp(C.white, amount) end
local function darken(color, amount) return color:Lerp(C.black, amount) end
Theme.lighten, Theme.darken = lighten, darken
Theme.ICON_LIGHT = 45 -- UIGradient rotation of the key light (top-left → bottom-right)

-- Fixed tones (hex); "base", "lite", "deep", "metal", "glass" and "glow" come from
-- the item's own colour (Theme.iconTones).
Theme.ICON_TONES = {
	steel = "D3DCE6", iron = "59616C", gold = "F2C14E", wood = "8A5A32", woodlite = "C99A62", leather = "7A4E2D",
	paper = "F2E6C8", cloth = "C9B68E", leaf = "5FAE45", stone = "7C828C", stonelite = "A7ADB5", bone = "EDE2C4",
	ink = "1A1F2A", flame = "FFB347", soil = "5A4030", plate = "E9E4DA", white = "FFFFFF", crust = "C98A4A",
}
function Theme.iconTones(def)
	local base = rgb(type(def) == "table" and type(def.color) == "string" and #def.color == 6 and def.color or "9FB4C8")
	local t = {base = base, lite = lighten(base, 0.4), deep = darken(base, 0.42), metal = base:Lerp(rgb("D3DCE6"), 0.55),
		glass = base:Lerp(rgb("E6F4FF"), 0.6), glow = lighten(base, 0.55)}
	for name, hex in pairs(Theme.ICON_TONES) do t[name] = rgb(hex) end
	return t
end

-- Layer authoring: positions and sizes are fractions of the icon box.
-- {x, y, w, h, rotation, tone, round, flags}; flags: o = outline, g = gleam (flat
-- white, translucent), a = translucency 0..1, ring = hollow (stroke only).
local function stick(x1, y1, x2, y2, width, tone, round, flags)
	local dx, dy = x2 - x1, y2 - y1
	return {(x1 + x2) / 2, (y1 + y2) / 2, width, math.sqrt(dx * dx + dy * dy), math.deg(math.atan2(dx, -dy)), tone, round or 0.35, flags or {o = true}}
end
local function box(x, y, w, h, tone, round, rotation, flags) return {x, y, w, h, rotation or 0, tone, round or 0.15, flags or {o = true}} end
local function disc(x, y, d, tone, flags) return {x, y, d, d, 0, tone, 0.5, flags or {o = true}} end
local function oval(x, y, w, h, tone, rotation, flags) return {x, y, w, h, rotation or 0, tone, 0.5, flags or {o = true}} end
local function gleam(x, y, w, h, rotation, alpha) return {x, y, w, h, rotation or 0, "white", 0.5, {g = true, a = alpha or 0.55}} end
local function halo(x, y, d, tone, alpha) return {x, y, d, d, 0, tone, 0.5, {a = alpha or 0.6, soft = true}} end
local function ring(x, y, w, h, tone, thickness) return {x, y, w, h, 0, tone, 0.5, {ring = thickness or 0.07}} end
local NO = {}

-- Motifs by family. Gear families are authored blade-up-right like the hotbar's held items.
Theme.ICON_MOTIFS = {
	-- Weapons
	sword = {stick(0.33, 0.67, 0.82, 0.18, 0.14, "steel", 0.3), stick(0.38, 0.62, 0.78, 0.22, 0.035, "white", 0.5, {g = true, a = 0.4}),
		stick(0.2, 0.55, 0.45, 0.8, 0.085, "base", 0.45), stick(0.33, 0.67, 0.18, 0.82, 0.075, "leather", 0.45), disc(0.16, 0.84, 0.1, "base"), disc(0.33, 0.67, 0.07, "lite", NO)},
	greatblade = {stick(0.34, 0.66, 0.86, 0.14, 0.21, "steel", 0.25), stick(0.4, 0.6, 0.8, 0.2, 0.05, "white", 0.5, {g = true, a = 0.45}),
		stick(0.18, 0.52, 0.48, 0.82, 0.1, "base", 0.4), stick(0.34, 0.66, 0.16, 0.84, 0.08, "leather", 0.45), disc(0.14, 0.86, 0.11, "base"), disc(0.34, 0.66, 0.09, "lite", NO)},
	dagger = {stick(0.42, 0.58, 0.78, 0.22, 0.13, "steel", 0.4), stick(0.46, 0.54, 0.74, 0.26, 0.03, "white", 0.5, {g = true, a = 0.4}),
		stick(0.3, 0.48, 0.52, 0.7, 0.08, "base", 0.45), stick(0.42, 0.58, 0.24, 0.76, 0.085, "leather", 0.45), disc(0.22, 0.78, 0.11, "base")},
	maul = {stick(0.2, 0.84, 0.6, 0.44, 0.08, "wood", 0.4), stick(0.44, 0.24, 0.8, 0.6, 0.26, "metal", 0.15), stick(0.5, 0.3, 0.74, 0.54, 0.05, "base", 0.2, NO),
		box(0.62, 0.42, 0.12, 0.12, "base", 0.2, 45), gleam(0.56, 0.32, 0.18, 0.05, 45, 0.5)},
	glaive = {stick(0.14, 0.88, 0.66, 0.36, 0.06, "wood", 0.4), oval(0.74, 0.27, 0.18, 0.36, "steel", 45), stick(0.66, 0.36, 0.78, 0.48, 0.07, "base", 0.4),
		stick(0.6, 0.42, 0.72, 0.3, 0.08, "base", 0.4), gleam(0.72, 0.24, 0.05, 0.22, 45, 0.45), disc(0.15, 0.87, 0.08, "base")},
	bow = {stick(0.58, 0.1, 0.36, 0.38, 0.075, "base", 0.5), stick(0.36, 0.38, 0.33, 0.62, 0.085, "leather", 0.4), stick(0.36, 0.62, 0.58, 0.9, 0.075, "base", 0.5),
		stick(0.6, 0.1, 0.6, 0.9, 0.018, "paper", 0.5, NO), stick(0.3, 0.5, 0.86, 0.5, 0.03, "woodlite", 0.5, NO), box(0.86, 0.5, 0.08, 0.08, "steel", 0.1, 45)},
	staff = {stick(0.24, 0.88, 0.6, 0.34, 0.07, "wood", 0.4), halo(0.68, 0.24, 0.46, "glow", 0.62), stick(0.57, 0.36, 0.56, 0.16, 0.035, "gold", 0.5),
		stick(0.72, 0.38, 0.84, 0.22, 0.035, "gold", 0.5), disc(0.68, 0.25, 0.24, "base"), gleam(0.63, 0.2, 0.08, 0.06, 0, 0.35)},
	wand = {stick(0.3, 0.82, 0.64, 0.4, 0.065, "base", 0.45), stick(0.27, 0.86, 0.38, 0.72, 0.075, "leather", 0.45), halo(0.7, 0.32, 0.38, "glow", 0.55),
		box(0.7, 0.32, 0.16, 0.16, "lite", 0.05, 45), box(0.7, 0.32, 0.16, 0.16, "white", 0.05, 0, {a = 0.4}), disc(0.7, 0.32, 0.08, "white", NO)},
	-- Armour
	helmet = {oval(0.5, 0.48, 0.64, 0.6, "metal"), box(0.5, 0.66, 0.7, 0.13, "base", 0.4), box(0.5, 0.52, 0.38, 0.06, "ink", 0.5, 0, NO),
		stick(0.5, 0.2, 0.5, 0.42, 0.09, "base", 0.5), gleam(0.37, 0.36, 0.12, 0.2, 20, 0.5)},
	chest = {box(0.5, 0.57, 0.5, 0.56, "metal", 0.22), oval(0.26, 0.37, 0.26, 0.22, "base", -15), oval(0.74, 0.37, 0.26, 0.22, "base", 15),
		box(0.5, 0.31, 0.26, 0.08, "base", 0.4), box(0.5, 0.78, 0.5, 0.08, "leather", 0.3), stick(0.5, 0.36, 0.5, 0.72, 0.04, "deep", 0.5, NO), gleam(0.38, 0.5, 0.07, 0.28, 0, 0.45)},
	legs = {box(0.5, 0.24, 0.56, 0.12, "leather", 0.3), box(0.37, 0.57, 0.2, 0.56, "metal", 0.25), box(0.63, 0.57, 0.2, 0.56, "metal", 0.25),
		disc(0.37, 0.55, 0.13, "base"), disc(0.63, 0.55, 0.13, "base"), gleam(0.33, 0.44, 0.05, 0.18, 0, 0.45)},
	boots = {box(0.35, 0.44, 0.19, 0.38, "base", 0.25), box(0.42, 0.68, 0.32, 0.15, "deep", 0.45), box(0.65, 0.44, 0.19, 0.38, "base", 0.25),
		box(0.72, 0.68, 0.32, 0.15, "deep", 0.45), box(0.35, 0.27, 0.23, 0.07, "metal", 0.3), box(0.65, 0.27, 0.23, 0.07, "metal", 0.3)},
	-- Tools
	pickaxe = {stick(0.22, 0.86, 0.6, 0.34, 0.075, "wood", 0.4), stick(0.3, 0.24, 0.62, 0.32, 0.1, "base", 0.5), stick(0.62, 0.32, 0.86, 0.6, 0.1, "base", 0.5),
		disc(0.6, 0.33, 0.12, "metal"), gleam(0.44, 0.26, 0.14, 0.03, 10, 0.5)},
	hatchet = {stick(0.26, 0.86, 0.56, 0.22, 0.075, "wood", 0.4), oval(0.66, 0.32, 0.28, 0.32, "base", 25), oval(0.76, 0.33, 0.08, 0.3, "steel", 25, NO),
		box(0.55, 0.26, 0.1, 0.12, "metal", 0.2, 25), gleam(0.64, 0.26, 0.1, 0.05, 25, 0.5)},
	rod = {stick(0.16, 0.88, 0.82, 0.14, 0.045, "wood", 0.5), disc(0.3, 0.72, 0.14, "metal"), stick(0.82, 0.14, 0.82, 0.62, 0.012, "paper", 0.5, NO),
		disc(0.82, 0.66, 0.11, "base"), box(0.82, 0.62, 0.11, 0.04, "white", 0.4, 0, NO), stick(0.16, 0.88, 0.26, 0.77, 0.06, "leather", 0.4)},
	hoe = {stick(0.24, 0.88, 0.62, 0.26, 0.07, "wood", 0.4), box(0.68, 0.3, 0.3, 0.12, "base", 0.25, -30), disc(0.62, 0.27, 0.08, "metal"), gleam(0.66, 0.27, 0.14, 0.03, -30, 0.5)},
	hammer = {stick(0.28, 0.86, 0.58, 0.4, 0.08, "wood", 0.4), stick(0.42, 0.24, 0.74, 0.56, 0.22, "base", 0.15), box(0.58, 0.4, 0.07, 0.25, "metal", 0.2, 45), gleam(0.5, 0.3, 0.14, 0.04, 45, 0.45)},
	crafttool = {stick(0.24, 0.84, 0.48, 0.6, 0.09, "wood", 0.4), stick(0.48, 0.6, 0.8, 0.28, 0.06, "metal", 0.3), box(0.48, 0.6, 0.12, 0.06, "base", 0.3, 45), oval(0.7, 0.72, 0.3, 0.16, "base", -20)},
	striker = {box(0.38, 0.6, 0.3, 0.22, "stone", 0.25, -20), stick(0.5, 0.44, 0.82, 0.66, 0.1, "base", 0.3), disc(0.6, 0.3, 0.07, "flame", NO), disc(0.7, 0.4, 0.05, "flame", NO), halo(0.62, 0.36, 0.26, "flame", 0.7)},
	-- Gathered goods
	ore = {oval(0.5, 0.6, 0.76, 0.58, "stone", -8), oval(0.44, 0.5, 0.5, 0.32, "stonelite", -8, NO), box(0.35, 0.56, 0.16, 0.16, "base", 0.15, 45), box(0.63, 0.67, 0.13, 0.13, "base", 0.15, 45),
		box(0.6, 0.45, 0.1, 0.1, "lite", 0.1, 45), gleam(0.33, 0.52, 0.05, 0.05, 45, 0.3)},
	crystal = {oval(0.5, 0.84, 0.64, 0.16, "stone"), box(0.34, 0.6, 0.15, 0.38, "deep", 0.12, -22), box(0.66, 0.6, 0.15, 0.36, "deep", 0.12, 22),
		box(0.5, 0.48, 0.2, 0.56, "base", 0.12), box(0.5, 0.22, 0.14, 0.14, "lite", 0.05, 45), gleam(0.45, 0.44, 0.04, 0.32, 0, 0.45)},
	bar = {box(0.5, 0.66, 0.74, 0.24, "deep", 0.12), box(0.5, 0.52, 0.58, 0.16, "base", 0.12), box(0.5, 0.42, 0.42, 0.1, "lite", 0.2), gleam(0.4, 0.5, 0.24, 0.04, 0, 0.45)},
	log = {oval(0.44, 0.54, 0.74, 0.36, "base", -25), stick(0.2, 0.62, 0.58, 0.44, 0.03, "deep", 0.5, NO), disc(0.76, 0.38, 0.3, "woodlite"), ring(0.76, 0.38, 0.19, 0.19, "wood", 0.04),
		disc(0.76, 0.38, 0.06, "wood", NO), oval(0.3, 0.36, 0.16, 0.08, "leaf", -30)},
	crop = {stick(0.5, 0.9, 0.5, 0.42, 0.05, "leaf", 0.5), oval(0.36, 0.6, 0.26, 0.1, "leaf", -35), oval(0.64, 0.64, 0.26, 0.1, "leaf", 35),
		disc(0.5, 0.33, 0.36, "base"), oval(0.5, 0.16, 0.16, 0.08, "leaf", 10), gleam(0.42, 0.26, 0.1, 0.08, -20, 0.5)},
	seed = {box(0.5, 0.6, 0.52, 0.5, "cloth", 0.4), box(0.5, 0.36, 0.3, 0.1, "leather", 0.4), oval(0.5, 0.3, 0.18, 0.1, "cloth", 0, NO),
		disc(0.36, 0.84, 0.1, "base"), disc(0.5, 0.88, 0.1, "base"), disc(0.64, 0.84, 0.1, "base"), oval(0.5, 0.6, 0.2, 0.14, "leaf", 20)},
	fish = {box(0.8, 0.52, 0.22, 0.22, "deep", 0.12, 45), oval(0.46, 0.52, 0.64, 0.38, "base"), oval(0.44, 0.62, 0.48, 0.14, "lite", 0, NO),
		box(0.48, 0.36, 0.18, 0.1, "deep", 0.3, -15), disc(0.28, 0.48, 0.08, "ink", NO), disc(0.27, 0.47, 0.03, "white", NO), gleam(0.44, 0.44, 0.24, 0.05, -5, 0.45)},
	-- Food and drink
	cooked = {oval(0.5, 0.7, 0.84, 0.3, "plate"), oval(0.5, 0.66, 0.64, 0.18, "white", 0, {a = 0.6}), oval(0.48, 0.56, 0.58, 0.28, "base"),
		stick(0.36, 0.48, 0.46, 0.64, 0.025, "deep", 0.5, NO), stick(0.5, 0.46, 0.6, 0.62, 0.025, "deep", 0.5, NO), oval(0.74, 0.5, 0.12, 0.07, "leaf", -30)},
	meal = {box(0.5, 0.68, 0.66, 0.32, "cloth", 0.45), oval(0.5, 0.52, 0.62, 0.22, "base"), oval(0.46, 0.48, 0.24, 0.08, "lite", 0, NO),
		stick(0.4, 0.34, 0.38, 0.14, 0.03, "white", 0.5, {g = true, a = 0.55}), stick(0.58, 0.34, 0.6, 0.12, 0.03, "white", 0.5, {g = true, a = 0.55})},
	pie = {oval(0.5, 0.64, 0.76, 0.36, "crust"), oval(0.5, 0.54, 0.68, 0.26, "base"), stick(0.34, 0.46, 0.62, 0.62, 0.035, "crust", 0.5, NO),
		stick(0.4, 0.62, 0.68, 0.46, 0.035, "crust", 0.5, NO), gleam(0.38, 0.5, 0.16, 0.05, 0, 0.4)},
	roast = {stick(0.26, 0.76, 0.42, 0.6, 0.08, "bone", 0.5), disc(0.24, 0.79, 0.1, "bone"), oval(0.6, 0.42, 0.5, 0.4, "base", -35), oval(0.54, 0.36, 0.2, 0.12, "lite", -35, NO)},
	potion = {disc(0.5, 0.64, 0.54, "glass", {o = true, a = 0.15}), oval(0.5, 0.7, 0.46, 0.3, "base", 0, NO), box(0.5, 0.31, 0.16, 0.18, "glass", 0.2, 0, {o = true, a = 0.15}),
		box(0.5, 0.19, 0.2, 0.09, "wood", 0.25), gleam(0.38, 0.56, 0.09, 0.16, 20, 0.4), halo(0.5, 0.66, 0.7, "glow", 0.78)},
	flask = {box(0.5, 0.6, 0.38, 0.54, "glass", 0.28, 0, {o = true, a = 0.15}), box(0.5, 0.68, 0.32, 0.36, "base", 0.25, 0, NO), box(0.5, 0.27, 0.14, 0.14, "glass", 0.2, 0, {o = true, a = 0.15}),
		box(0.5, 0.17, 0.18, 0.08, "wood", 0.25), box(0.5, 0.6, 0.34, 0.12, "paper", 0.1), gleam(0.4, 0.52, 0.05, 0.26, 0, 0.45)},
	-- Ammunition, runes and gems
	arrow = {stick(0.18, 0.82, 0.76, 0.24, 0.04, "wood", 0.5), box(0.78, 0.22, 0.14, 0.14, "base", 0.1, 45), stick(0.16, 0.76, 0.26, 0.74, 0.06, "lite", 0.5),
		stick(0.24, 0.84, 0.26, 0.74, 0.06, "lite", 0.5)},
	arrowhead = {box(0.3, 0.64, 0.18, 0.18, "deep", 0.1, 45), box(0.7, 0.64, 0.18, 0.18, "deep", 0.1, 45), box(0.5, 0.42, 0.22, 0.22, "base", 0.1, 45), gleam(0.47, 0.38, 0.06, 0.06, 45, 0.45)},
	shaft = {stick(0.2, 0.8, 0.72, 0.28, 0.04, "wood", 0.5), stick(0.28, 0.84, 0.8, 0.32, 0.04, "woodlite", 0.5), stick(0.14, 0.74, 0.66, 0.22, 0.04, "wood", 0.5), box(0.46, 0.56, 0.3, 0.06, "base", 0.4, -45)},
	rune = {halo(0.5, 0.5, 0.86, "glow", 0.68), box(0.5, 0.5, 0.58, 0.68, "stone", 0.28), stick(0.42, 0.3, 0.58, 0.7, 0.05, "base", 0.5, NO),
		stick(0.6, 0.32, 0.38, 0.56, 0.05, "base", 0.5, NO), disc(0.5, 0.5, 0.12, "lite", NO), gleam(0.34, 0.26, 0.12, 0.05, 0, 0.4)},
	glyph = {halo(0.5, 0.5, 0.86, "glow", 0.7), disc(0.5, 0.5, 0.66, "deep"), ring(0.5, 0.5, 0.5, 0.5, "base", 0.05), stick(0.5, 0.3, 0.5, 0.7, 0.04, "lite", 0.5, NO),
		stick(0.33, 0.6, 0.67, 0.4, 0.04, "lite", 0.5, NO), disc(0.5, 0.5, 0.1, "white", NO)},
	gem = {halo(0.5, 0.5, 0.82, "glow", 0.72), box(0.5, 0.52, 0.46, 0.46, "base", 0.1, 45), box(0.5, 0.45, 0.22, 0.14, "lite", 0.15, 0, NO), gleam(0.42, 0.42, 0.06, 0.06, 45, 0.35)},
	roughgem = {oval(0.5, 0.6, 0.72, 0.54, "stone", 10), box(0.44, 0.52, 0.22, 0.22, "base", 0.1, 45), box(0.62, 0.64, 0.14, 0.14, "lite", 0.1, 45), gleam(0.42, 0.48, 0.05, 0.05, 45, 0.35)},
	-- Jewellery and trinkets
	ring = {ring(0.5, 0.6, 0.56, 0.56, "gold", 0.08), box(0.5, 0.4, 0.18, 0.09, "gold", 0.3), box(0.5, 0.31, 0.22, 0.22, "base", 0.1, 45), box(0.5, 0.31, 0.1, 0.1, "white", 0.1, 45, {g = true, a = 0.45}), gleam(0.33, 0.58, 0.05, 0.16, 0, 0.5)},
	amulet = {ring(0.5, 0.34, 0.56, 0.48, "gold", 0.04), disc(0.5, 0.66, 0.36, "gold"), disc(0.5, 0.66, 0.24, "base"), gleam(0.45, 0.61, 0.08, 0.06, 0, 0.35)},
	charm = {stick(0.5, 0.18, 0.5, 0.36, 0.04, "gold", 0.5, NO), ring(0.5, 0.2, 0.14, 0.14, "gold", 0.03), box(0.5, 0.58, 0.4, 0.4, "base", 0.22, 45), disc(0.5, 0.58, 0.14, "lite"), gleam(0.42, 0.5, 0.08, 0.05, 45, 0.45)},
	lantern = {ring(0.5, 0.16, 0.18, 0.14, "iron", 0.03), box(0.5, 0.27, 0.36, 0.1, "iron", 0.3), box(0.5, 0.56, 0.38, 0.46, "glass", 0.12, 0, {o = true, a = 0.25}),
		halo(0.5, 0.58, 0.5, "flame", 0.5), oval(0.5, 0.6, 0.16, 0.24, "flame", 0, NO), stick(0.32, 0.34, 0.32, 0.78, 0.04, "iron", 0.3, NO), stick(0.68, 0.34, 0.68, 0.78, 0.04, "iron", 0.3, NO), box(0.5, 0.82, 0.44, 0.08, "iron", 0.3)},
	crown = {box(0.5, 0.66, 0.68, 0.2, "gold", 0.15), box(0.26, 0.48, 0.12, 0.24, "gold", 0.2), box(0.5, 0.42, 0.13, 0.32, "gold", 0.2), box(0.74, 0.48, 0.12, 0.24, "gold", 0.2),
		disc(0.26, 0.34, 0.08, "base"), disc(0.5, 0.24, 0.09, "base"), disc(0.74, 0.34, 0.08, "base"), disc(0.5, 0.66, 0.12, "base"), gleam(0.36, 0.62, 0.16, 0.04, 0, 0.45)},
	seal = {stick(0.4, 0.7, 0.32, 0.92, 0.1, "deep", 0.2), stick(0.6, 0.7, 0.68, 0.92, 0.1, "deep", 0.2), disc(0.5, 0.5, 0.62, "base"), disc(0.5, 0.5, 0.42, "deep", NO),
		box(0.5, 0.5, 0.18, 0.18, "lite", 0.15, 45), gleam(0.38, 0.38, 0.12, 0.06, -30, 0.4)},
	orb = {halo(0.5, 0.46, 0.8, "glow", 0.6), disc(0.5, 0.46, 0.56, "base"), oval(0.4, 0.36, 0.16, 0.1, "white", -30, {g = true, a = 0.35}), box(0.5, 0.84, 0.4, 0.08, "gold", 0.3), stick(0.42, 0.72, 0.36, 0.84, 0.05, "gold", 0.3), stick(0.58, 0.72, 0.64, 0.84, 0.05, "gold", 0.3)},
	tome = {box(0.54, 0.56, 0.52, 0.66, "paper", 0.08), box(0.48, 0.54, 0.54, 0.68, "base", 0.1), box(0.24, 0.54, 0.06, 0.68, "deep", 0.3, 0, NO),
		disc(0.48, 0.48, 0.18, "gold"), box(0.48, 0.48, 0.08, 0.08, "base", 0.1, 45, NO), box(0.74, 0.56, 0.06, 0.16, "gold", 0.3)},
	quiver = {stick(0.36, 0.86, 0.58, 0.34, 0.24, "leather", 0.3), stick(0.5, 0.36, 0.6, 0.12, 0.03, "wood", 0.5, NO), stick(0.58, 0.36, 0.72, 0.14, 0.03, "wood", 0.5, NO),
		box(0.6, 0.12, 0.1, 0.1, "base", 0.1, 45), box(0.73, 0.14, 0.1, 0.1, "base", 0.1, 45), stick(0.38, 0.66, 0.6, 0.72, 0.05, "base", 0.3)},
	cloak = {box(0.5, 0.58, 0.62, 0.64, "base", 0.3), box(0.5, 0.62, 0.3, 0.56, "deep", 0.35, 0, NO), oval(0.5, 0.3, 0.52, 0.16, "deep"), disc(0.5, 0.32, 0.12, "gold"), gleam(0.3, 0.5, 0.05, 0.3, 0, 0.45)},
	gauntlet = {box(0.5, 0.62, 0.42, 0.44, "metal", 0.3), box(0.36, 0.34, 0.08, 0.2, "metal", 0.4), box(0.46, 0.3, 0.08, 0.22, "metal", 0.4), box(0.56, 0.3, 0.08, 0.22, "metal", 0.4),
		box(0.66, 0.36, 0.08, 0.18, "metal", 0.4), box(0.5, 0.84, 0.48, 0.1, "base", 0.3), disc(0.5, 0.6, 0.12, "base")},
	lens = {ring(0.44, 0.44, 0.54, 0.54, "gold", 0.06), disc(0.44, 0.44, 0.44, "glass", {a = 0.35}), stick(0.62, 0.62, 0.86, 0.86, 0.08, "wood", 0.4), gleam(0.36, 0.36, 0.1, 0.06, -45, 0.35)},
	-- Pets and pet items
	pet = {oval(0.48, 0.52, 0.56, 0.7, "base"), disc(0.38, 0.4, 0.12, "lite", NO), disc(0.58, 0.64, 0.1, "lite", NO), disc(0.72, 0.76, 0.26, "paper"),
		disc(0.72, 0.8, 0.1, "deep", NO), disc(0.65, 0.71, 0.05, "deep", NO), disc(0.72, 0.68, 0.05, "deep", NO), disc(0.79, 0.71, 0.05, "deep", NO), gleam(0.38, 0.34, 0.08, 0.12, -20, 0.4)},
	collar = {ring(0.5, 0.46, 0.66, 0.44, "base", 0.08), box(0.5, 0.7, 0.12, 0.08, "metal", 0.3), disc(0.5, 0.78, 0.18, "gold"), gleam(0.47, 0.75, 0.05, 0.04, 0, 0.4)},
	candy = {box(0.24, 0.5, 0.16, 0.22, "lite", 0.1, 45), box(0.76, 0.5, 0.16, 0.22, "lite", 0.1, 45), oval(0.5, 0.5, 0.42, 0.32, "base"),
		stick(0.42, 0.38, 0.5, 0.62, 0.04, "white", 0.5, {g = true, a = 0.3}), stick(0.54, 0.36, 0.62, 0.6, 0.04, "white", 0.5, {g = true, a = 0.3})},
	bell = {box(0.5, 0.28, 0.2, 0.08, "base", 0.4), box(0.5, 0.52, 0.44, 0.42, "gold", 0.45), box(0.5, 0.74, 0.58, 0.09, "gold", 0.4), disc(0.5, 0.83, 0.1, "iron"), gleam(0.4, 0.46, 0.06, 0.18, 0, 0.45)},
	sprig = {stick(0.34, 0.86, 0.6, 0.2, 0.04, "leaf", 0.5), oval(0.42, 0.56, 0.26, 0.12, "base", -40), oval(0.6, 0.42, 0.26, 0.12, "base", 30), oval(0.52, 0.26, 0.22, 0.11, "lite", -30), disc(0.62, 0.2, 0.08, "gold")},
	-- Scrolls, banners and containers
	scroll = {box(0.5, 0.5, 0.52, 0.52, "paper", 0.06), box(0.5, 0.24, 0.62, 0.1, "woodlite", 0.5), box(0.5, 0.76, 0.62, 0.1, "woodlite", 0.5),
		box(0.46, 0.42, 0.32, 0.03, "ink", 0.5, 0, {a = 0.45}), box(0.44, 0.52, 0.28, 0.03, "ink", 0.5, 0, {a = 0.45}), disc(0.64, 0.6, 0.15, "base")},
	banner = {stick(0.3, 0.92, 0.3, 0.1, 0.05, "wood", 0.5), box(0.54, 0.4, 0.44, 0.5, "base", 0.05), box(0.43, 0.68, 0.16, 0.16, "base", 0.05, 45), box(0.65, 0.68, 0.16, 0.16, "base", 0.05, 45),
		disc(0.54, 0.38, 0.16, "gold"), box(0.54, 0.16, 0.5, 0.05, "gold", 0.4), disc(0.3, 0.1, 0.07, "gold")},
	casket = {box(0.5, 0.64, 0.7, 0.4, "wood", 0.1), box(0.5, 0.38, 0.7, 0.2, "base", 0.4), box(0.3, 0.56, 0.06, 0.48, "gold", 0.2, 0, NO), box(0.7, 0.56, 0.06, 0.48, "gold", 0.2, 0, NO),
		box(0.5, 0.52, 0.12, 0.14, "gold", 0.25), gleam(0.4, 0.34, 0.2, 0.04, 0, 0.45)},
	coffer = {box(0.5, 0.62, 0.68, 0.42, "iron", 0.12), box(0.5, 0.38, 0.68, 0.16, "base", 0.35), box(0.5, 0.62, 0.68, 0.06, "base", 0.2, 0, NO), box(0.5, 0.54, 0.14, 0.16, "gold", 0.25), gleam(0.36, 0.36, 0.2, 0.04, 0, 0.45)},
	spade = {stick(0.5, 0.12, 0.5, 0.6, 0.065, "wood", 0.4), box(0.5, 0.13, 0.22, 0.07, "wood", 0.4), box(0.5, 0.72, 0.34, 0.34, "base", 0.38), gleam(0.42, 0.68, 0.05, 0.16, 0, 0.45)},
	pouch = {box(0.5, 0.62, 0.58, 0.52, "base", 0.42), box(0.5, 0.35, 0.36, 0.12, "deep", 0.3), box(0.5, 0.41, 0.42, 0.05, "gold", 0.4), disc(0.5, 0.64, 0.14, "lite"), gleam(0.36, 0.56, 0.06, 0.16, 0, 0.4)},
	trap = {box(0.5, 0.6, 0.68, 0.46, "wood", 0.06), stick(0.32, 0.4, 0.32, 0.82, 0.03, "iron", 0.3, NO), stick(0.5, 0.4, 0.5, 0.82, 0.03, "iron", 0.3, NO),
		stick(0.68, 0.4, 0.68, 0.82, 0.03, "iron", 0.3, NO), box(0.5, 0.36, 0.72, 0.08, "base", 0.3), ring(0.5, 0.22, 0.16, 0.14, "iron", 0.03)},
	fuel = {box(0.5, 0.64, 0.58, 0.4, "base", 0.15), box(0.5, 0.52, 0.58, 0.08, "deep", 0.2, 0, NO), halo(0.5, 0.32, 0.4, "flame", 0.6), oval(0.5, 0.32, 0.18, 0.28, "flame")},
	cog = {box(0.5, 0.5, 0.16, 0.8, "base", 0.15), box(0.5, 0.5, 0.16, 0.8, "base", 0.15, 45), box(0.5, 0.5, 0.16, 0.8, "base", 0.15, 90), box(0.5, 0.5, 0.16, 0.8, "base", 0.15, 135),
		disc(0.5, 0.5, 0.6, "base"), disc(0.5, 0.5, 0.24, "deep"), gleam(0.4, 0.38, 0.12, 0.05, -30, 0.45)},
	gloves = {box(0.5, 0.58, 0.42, 0.42, "base", 0.32), box(0.36, 0.32, 0.09, 0.22, "base", 0.45), box(0.47, 0.28, 0.09, 0.24, "base", 0.45), box(0.58, 0.3, 0.09, 0.22, "base", 0.45),
		box(0.72, 0.52, 0.09, 0.2, "base", 0.45, 40), box(0.5, 0.84, 0.46, 0.1, "deep", 0.3)},
	salve = {box(0.5, 0.62, 0.52, 0.42, "glass", 0.22, 0, {o = true, a = 0.2}), oval(0.5, 0.64, 0.42, 0.24, "base", 0, NO), box(0.5, 0.37, 0.56, 0.1, "wood", 0.3), gleam(0.36, 0.6, 0.05, 0.2, 0, 0.45)},
	compost = {oval(0.5, 0.68, 0.74, 0.36, "soil"), oval(0.46, 0.6, 0.44, 0.2, "base", 0, NO), stick(0.5, 0.56, 0.5, 0.32, 0.03, "leaf", 0.5, NO), oval(0.42, 0.32, 0.14, 0.07, "leaf", -30), oval(0.58, 0.3, 0.14, 0.07, "leaf", 30)},
	bait = {oval(0.5, 0.5, 0.5, 0.24, "base", -30), disc(0.38, 0.58, 0.06, "lite", NO), disc(0.5, 0.5, 0.06, "lite", NO), ring(0.7, 0.32, 0.12, 0.12, "iron", 0.03), stick(0.28, 0.66, 0.2, 0.84, 0.04, "steel", 0.5)},
	remains = {stick(0.24, 0.8, 0.76, 0.66, 0.08, "bone", 0.5), stick(0.3, 0.6, 0.72, 0.84, 0.07, "bone", 0.5), disc(0.5, 0.42, 0.38, "bone"), disc(0.43, 0.42, 0.09, "ink", NO), disc(0.57, 0.42, 0.09, "ink", NO), box(0.5, 0.56, 0.18, 0.08, "bone", 0.3)},
	-- Crafting materials
	dust = {oval(0.5, 0.7, 0.74, 0.34, "base"), oval(0.5, 0.6, 0.46, 0.22, "lite", 0, NO), disc(0.32, 0.38, 0.05, "white", {g = true, a = 0.3}), disc(0.66, 0.32, 0.04, "white", {g = true, a = 0.3}), disc(0.52, 0.26, 0.03, "white", {g = true, a = 0.3})},
	essence = {halo(0.5, 0.5, 0.86, "glow", 0.55), disc(0.5, 0.52, 0.46, "base"), oval(0.44, 0.44, 0.2, 0.1, "white", -30, {g = true, a = 0.35}), stick(0.36, 0.72, 0.66, 0.3, 0.04, "lite", 0.5, NO)},
	core = {halo(0.5, 0.5, 0.86, "glow", 0.6), ring(0.5, 0.5, 0.72, 0.72, "metal", 0.07), disc(0.5, 0.5, 0.5, "deep"), disc(0.5, 0.5, 0.28, "lite"), gleam(0.44, 0.44, 0.08, 0.06, 0, 0.35)},
	geode = {oval(0.5, 0.56, 0.7, 0.58, "stone"), oval(0.5, 0.56, 0.48, 0.38, "deep", 0, NO), box(0.42, 0.56, 0.12, 0.12, "base", 0.1, 45, NO), box(0.58, 0.58, 0.12, 0.12, "lite", 0.1, 45, NO), box(0.5, 0.48, 0.1, 0.1, "lite", 0.1, 45, NO)},
	ember = {halo(0.5, 0.58, 0.8, "flame", 0.62), disc(0.5, 0.6, 0.52, "iron"), stick(0.36, 0.5, 0.56, 0.7, 0.03, "flame", 0.5, NO), stick(0.56, 0.44, 0.64, 0.66, 0.03, "flame", 0.5, NO), oval(0.5, 0.36, 0.14, 0.22, "base")},
	glass = {box(0.5, 0.52, 0.56, 0.56, "glass", 0.2, 12, {o = true, a = 0.2}), box(0.5, 0.52, 0.38, 0.38, "lite", 0.2, 12, {a = 0.6}), gleam(0.38, 0.4, 0.05, 0.26, 12, 0.35)},
	vial = {box(0.5, 0.56, 0.22, 0.62, "glass", 0.5, 0, {o = true, a = 0.15}), box(0.5, 0.66, 0.17, 0.38, "base", 0.5, 0, NO), box(0.5, 0.22, 0.2, 0.08, "wood", 0.3), gleam(0.46, 0.5, 0.03, 0.3, 0, 0.4)},
	jelly = {oval(0.5, 0.6, 0.62, 0.5, "base", 0, {o = true, a = 0.2}), disc(0.4, 0.58, 0.1, "lite", NO), disc(0.58, 0.68, 0.07, "lite", NO), gleam(0.4, 0.46, 0.16, 0.07, -20, 0.35)},
	hide = {box(0.5, 0.52, 0.6, 0.56, "base", 0.38, -8), box(0.24, 0.26, 0.14, 0.14, "base", 0.4, 30), box(0.76, 0.26, 0.14, 0.14, "base", 0.4, -30),
		box(0.26, 0.78, 0.14, 0.14, "base", 0.4, -30), box(0.74, 0.78, 0.14, 0.14, "base", 0.4, 30), oval(0.5, 0.52, 0.32, 0.3, "lite", -8, NO)},
	leather = {box(0.5, 0.62, 0.66, 0.36, "deep", 0.14), box(0.5, 0.48, 0.66, 0.36, "base", 0.14), box(0.5, 0.48, 0.56, 0.02, "paper", 0.5, 0, {a = 0.4}), gleam(0.36, 0.38, 0.22, 0.04, 0, 0.45)},
	thread = {box(0.5, 0.52, 0.34, 0.44, "base", 0.2), box(0.5, 0.28, 0.5, 0.08, "wood", 0.4), box(0.5, 0.76, 0.5, 0.08, "wood", 0.4),
		box(0.5, 0.46, 0.34, 0.03, "lite", 0.5, 0, NO), box(0.5, 0.58, 0.34, 0.03, "lite", 0.5, 0, NO), stick(0.66, 0.54, 0.86, 0.84, 0.025, "base", 0.5, NO)},
	cloth = {oval(0.44, 0.58, 0.64, 0.4, "base", -20), disc(0.74, 0.46, 0.3, "lite"), ring(0.74, 0.46, 0.16, 0.16, "deep", 0.03), stick(0.22, 0.74, 0.5, 0.82, 0.03, "lite", 0.5, NO)},
	scale = {oval(0.36, 0.38, 0.3, 0.26, "deep"), oval(0.64, 0.38, 0.3, 0.26, "deep"), oval(0.5, 0.58, 0.34, 0.3, "base"), oval(0.32, 0.66, 0.26, 0.22, "base"),
		oval(0.68, 0.66, 0.26, 0.22, "base"), gleam(0.46, 0.52, 0.1, 0.05, -20, 0.4)},
	shell = {box(0.5, 0.84, 0.18, 0.08, "deep", 0.3), oval(0.5, 0.56, 0.68, 0.52, "base"), stick(0.5, 0.82, 0.5, 0.32, 0.03, "lite", 0.5, NO), stick(0.5, 0.82, 0.3, 0.4, 0.03, "lite", 0.5, NO), stick(0.5, 0.82, 0.7, 0.4, 0.03, "lite", 0.5, NO)},
	pearl = {oval(0.5, 0.72, 0.6, 0.2, "deep"), disc(0.5, 0.52, 0.42, "base"), disc(0.42, 0.44, 0.12, "white", {g = true, a = 0.3}), halo(0.5, 0.52, 0.66, "glow", 0.7)},
	fang = {stick(0.36, 0.22, 0.58, 0.8, 0.16, "bone", 0.5), stick(0.58, 0.8, 0.62, 0.86, 0.06, "bone", 0.5), stick(0.32, 0.2, 0.44, 0.28, 0.14, "base", 0.4), gleam(0.42, 0.4, 0.04, 0.24, -20, 0.4)},
	feather = {oval(0.54, 0.44, 0.26, 0.66, "base", 40), oval(0.58, 0.4, 0.12, 0.5, "lite", 40, NO), stick(0.24, 0.84, 0.74, 0.18, 0.025, "paper", 0.5, NO)},
	key = {ring(0.3, 0.3, 0.3, 0.3, "gold", 0.07), stick(0.38, 0.38, 0.8, 0.8, 0.075, "gold", 0.4), box(0.7, 0.8, 0.08, 0.14, "gold", 0.2, 45), box(0.78, 0.7, 0.08, 0.12, "gold", 0.2, 45), disc(0.3, 0.3, 0.1, "base")},
	coin = {oval(0.5, 0.76, 0.66, 0.22, "deep"), oval(0.5, 0.67, 0.66, 0.22, "base"), oval(0.5, 0.58, 0.66, 0.22, "base"), oval(0.5, 0.49, 0.66, 0.24, "lite"), box(0.5, 0.49, 0.12, 0.08, "deep", 0.1, 45, NO)},
	kit = {box(0.5, 0.62, 0.7, 0.42, "base", 0.12), ring(0.5, 0.36, 0.3, 0.18, "iron", 0.04), box(0.5, 0.56, 0.7, 0.06, "deep", 0.2, 0, NO), box(0.5, 0.58, 0.12, 0.12, "gold", 0.25)},
	hilt = {stick(0.28, 0.82, 0.5, 0.6, 0.08, "leather", 0.45), stick(0.36, 0.46, 0.64, 0.74, 0.1, "base", 0.4), stick(0.5, 0.6, 0.66, 0.44, 0.07, "steel", 0.3), disc(0.25, 0.85, 0.12, "base"), gleam(0.48, 0.56, 0.1, 0.03, 45, 0.45)},
	meat = {stick(0.26, 0.76, 0.42, 0.6, 0.07, "bone", 0.5), oval(0.58, 0.46, 0.56, 0.42, "base", -25), oval(0.66, 0.4, 0.2, 0.14, "lite", -25, NO), disc(0.24, 0.78, 0.1, "bone")},
	ink = {disc(0.46, 0.64, 0.46, "ink"), box(0.46, 0.38, 0.16, 0.1, "ink", 0.3), stick(0.5, 0.42, 0.8, 0.1, 0.03, "paper", 0.5, NO), oval(0.72, 0.2, 0.12, 0.28, "base", 40), gleam(0.38, 0.58, 0.06, 0.1, 0, 0.4)},
}

-- Rules (data-driven by kind; another team's new items fall in automatically).
Theme.ICON_KIND = {weapon = "sword", armor = "chest", tool = "pickaxe", resource = "ore", consumable = "potion", accessory = "charm",
	pet = "pet", petitem = "charm", trail = "scroll", material = "essence", shield = "seal"}
Theme.ICON_SLOT = {helmet = "helmet", chest = "chest", legs = "legs", boots = "boots"}
Theme.ICON_TOOL = {Pickaxe = "pickaxe", Hatchet = "hatchet", Rod = "rod", Hoe = "hoe", Hammer = "hammer"}
Theme.ICON_SKILL = {Mining = "ore", Woodcutting = "log", Fishing = "fish", Farming = "crop"}
Theme.ICON_HELD = {sword = "sword", greatblade = "greatblade", dagger = "dagger", maul = "maul", glaive = "glaive", shortbow = "bow", longbow = "bow",
	staff = "staff", wand = "wand", shield = "seal", pickaxe = "pickaxe", hatchet = "hatchet", rod = "rod", hoe = "hoe", hammer = "hammer"}
-- Weapon silhouettes by name (Data.Held's patterns): checked in order.
Theme.ICON_WEAPON_NAMES = {{"Greatblade", "greatblade"}, {"Cleaver", "greatblade"}, {"Claymore", "greatblade"}, {"Dagger", "dagger"}, {"Fang", "dagger"},
	{"Knife", "dagger"}, {"Maul", "maul"}, {"Hammer", "maul"}, {"Glaive", "glaive"}, {"Spear", "glaive"}, {"Halberd", "glaive"}}
Theme.ICON_CATEGORY = {ammo = "arrow", bait = "bait", beaconTool = "striker", craftTool = "crafttool", fertiliser = "compost", gem = "gem", roughGem = "roughgem",
	gloves = "gloves", glyph = "glyph", tablet = "glyph", pouch = "pouch", remains = "remains", rune = "rune", shard = "crystal", trap = "trap",
	treatment = "salve", warp = "scroll", workerChest = "coffer", workerFuel = "fuel", workerUpgrade = "cog", banner = "banner", casket = "casket",
	emote = "scroll", scroll = "scroll", spade = "spade", teleport = "scroll", potion = "potion", buff = "flask", food = "meal", seed = "seed"}
-- Id keywords per kind (first match wins), checked after the category.
Theme.ICON_KEYWORDS = {
	material = {{"Ingot", "bar"}, {"Heads", "arrowhead"}, {"Shaft", "shaft"}, {"Bowstring", "thread"}, {"String", "thread"}, {"Thread", "thread"},
		{"Silk", "thread"}, {"Coil", "thread"}, {"Bolt", "cloth"}, {"Leather", "leather"}, {"Hide", "hide"}, {"Pelt", "hide"}, {"Plate", "scale"},
		{"Scale", "scale"}, {"Chitin", "scale"}, {"Shell", "shell"}, {"Pearl", "pearl"}, {"Knot", "pearl"}, {"Fang", "fang"}, {"Barb", "fang"},
		{"Horn", "fang"}, {"Plume", "feather"}, {"Feather", "feather"}, {"Quill", "feather"}, {"Keystone", "key"}, {"Key", "key"}, {"Dust", "dust"},
		{"Grit", "dust"}, {"Ash", "dust"}, {"Sand", "dust"}, {"sand", "dust"}, {"Spore", "dust"}, {"Starcore", "core"}, {"Core", "core"}, {"Geode", "geode"},
		{"Cinder", "ember"}, {"Candy", "candy"}, {"Orb", "orb"}, {"Bauble", "orb"}, {"Globe", "orb"}, {"Lens", "lens"}, {"Vial", "vial"},
		{"Oil", "vial"}, {"Ichor", "vial"}, {"MoltenGlass", "glass"}, {"Glass", "glass"}, {"Jelly", "jelly"}, {"Shard", "crystal"},
		{"Crystal", "crystal"}, {"Stormglass", "crystal"}, {"Fragment", "crystal"}, {"Tome", "tome"}, {"Ink", "ink"}, {"Seal", "seal"},
		{"Sigil", "seal"}, {"Crest", "seal"}, {"Mark", "seal"}, {"Token", "coin"}, {"Skymark", "coin"}, {"Satchel", "pouch"}, {"Kit", "kit"},
		{"Hilt", "hilt"}, {"Haunch", "meat"}, {"Shank", "meat"}, {"Raw", "meat"}, {"Essence", "essence"}},
	accessory = {{"Ring", "ring"}, {"Band", "ring"}, {"Signet", "ring"}, {"Necklace", "amulet"}, {"Amulet", "amulet"}, {"Locket", "amulet"},
		{"Pendant", "amulet"}, {"Pearl", "amulet"}, {"Heartstone", "amulet"}, {"Medallion", "amulet"}, {"Lantern", "lantern"}, {"Censer", "lantern"},
		{"Crown", "crown"}, {"Halo", "crown"}, {"Diadem", "crown"}, {"Sigil", "seal"}, {"Seal", "seal"}, {"Emblem", "seal"}, {"Crest", "seal"},
		{"Orb", "orb"}, {"Orrery", "orb"}, {"Astrolabe", "orb"}, {"Compass", "orb"}, {"Tome", "tome"}, {"Quiver", "quiver"}, {"Mantle", "cloak"},
		{"Gauntlet", "gauntlet"}, {"Bracer", "gauntlet"}, {"Cord", "ring"}, {"Monocle", "lens"}, {"Bead", "pearl"}},
	petitem = {{"Collar", "collar"}, {"Tag", "collar"}, {"Candy", "candy"}, {"Bell", "bell"}, {"Lens", "lens"}, {"Prism", "crystal"}, {"Pendant", "amulet"},
		{"Ribbon", "sprig"}, {"Clover", "sprig"}, {"Sprig", "sprig"}, {"Pouch", "pouch"}, {"Anklet", "ring"}, {"Thimble", "charm"}},
	consumable = {{"Tonic", "potion"}, {"Cooked", "cooked"}, {"Pie", "pie"}, {"Tart", "pie"}, {"Roast", "roast"}, {"Skewer", "roast"}, {"Haunch", "roast"},
		{"Stew", "meal"}, {"Broth", "meal"}, {"Banquet", "meal"}, {"Feast", "meal"}, {"Ration", "meal"}, {"Cocoa", "meal"}},
	resource = {{"Seeds", "seed"}, {"Spores", "seed"}, {"Bulb", "seed"}, {"Pit", "seed"}, {"Bud", "seed"}, {"Aetherite", "crystal"}, {"Prismite", "crystal"}, {"Celestium", "crystal"}},
	trail = {{"Spade", "spade"}, {"Casket", "casket"}, {"Banner", "banner"}},
	weapon = {}, armor = {}, tool = {}, pet = {},
}
-- Kinds whose id keywords beat the category (a "food" that is a Cooked fish).
Theme.ICON_KEYWORD_FIRST = {consumable = true}
-- Compressed materials keep the family of the item they compress.
Theme.ICON_MODIFIERS = {{"Condensed", "condensed"}, {"Radiant", "radiant"}}
Theme.ICON_GEAR = {weapon = true, armor = true, tool = true, accessory = true}
Theme.items = nil -- Data.Items, set by Theme.useItems (resolves a compressed item's base)
function Theme.useItems(items) if type(items) == "table" then Theme.items = items end end

local function keyword(list, id)
	for _, entry in ipairs(list or {}) do if string.find(id, entry[1], 1, true) then return entry[2] end end
	return nil
end
local function weaponFamily(def)
	if type(def.heldClass) == "string" and Theme.ICON_HELD[def.heldClass] then return Theme.ICON_HELD[def.heldClass], "held" end
	local name = tostring(def.name or def.id or "")
	if def.style == "ranged" then return "bow", "style" end
	if def.style == "magic" then
		local wand = string.find(name, "Wand", 1, true) ~= nil or (type(def.magic) == "table" and type(def.magic.elements) == "table" and #def.magic.elements == 0)
		return if wand then "wand" else "staff", "style"
	end
	local named = keyword(Theme.ICON_WEAPON_NAMES, name)
	if named then return named, "name" end
	return "sword", "kind"
end
-- Pure: def (+ optional items table) → icon spec {family, rule, modifier, rarity,
-- rank, gear, halo, color, key}; rule says which data decided ("fallback" only
-- for a missing def or an unknown kind).
function Theme.iconSpec(def, items)
	items = items or Theme.items
	if type(def) ~= "table" then return {family = "gem", rule = "fallback", rarity = "Common", rank = 1, key = "fallback"} end
	local id = tostring(def.id or def.name or "")
	local kind, family, rule, modifier = def.kind, nil, nil, nil
	for _, m in ipairs(Theme.ICON_MODIFIERS) do
		if string.sub(id, 1, #m[1]) == m[1] and #id > #m[1] then
			local baseId = string.sub(id, #m[1] + 1)
			local base = type(items) == "table" and items[baseId]
			if type(base) == "table" and base ~= def then
				local inner = Theme.iconSpec(base, items)
				family, rule, modifier = inner.family, "condensed:" .. inner.rule, m[2]
			end
		end
	end
	if not family then
		if kind == "weapon" then family, rule = weaponFamily(def)
		elseif kind == "armor" then family, rule = Theme.ICON_SLOT[def.slot], "slot"
		elseif kind == "tool" then family, rule = Theme.ICON_TOOL[def.toolKind] or Theme.ICON_HELD[def.heldClass or ""], "tool"
		end
		if not family and Theme.ICON_KEYWORD_FIRST[kind or ""] then
			local hit = keyword(Theme.ICON_KEYWORDS[kind], id)
			if hit then family, rule = hit, "keyword" end
		end
		if not family and def.category and Theme.ICON_CATEGORY[def.category] then family, rule = Theme.ICON_CATEGORY[def.category], "category" end
		if not family and kind == "accessory" and def.category == "jewellery" then
			family, rule = keyword(Theme.ICON_KEYWORDS.accessory, id), "keyword"
			if not family then family, rule = "orb", "category" end
		end
		if not family and Theme.ICON_KEYWORDS[kind or ""] then
			local hit = keyword(Theme.ICON_KEYWORDS[kind], id)
			if hit then family, rule = hit, "keyword" end
		end
		if not family and kind == "resource" and Theme.ICON_SKILL[def.skill or ""] then family, rule = Theme.ICON_SKILL[def.skill], "skill" end
		if not family and kind == "material" and def.heldClass == "striker" then family, rule = "striker", "held" end
		if not family and Theme.ICON_KIND[kind or ""] then family, rule = Theme.ICON_KIND[kind], "kind" end
	end
	if not family or not Theme.ICON_MOTIFS[family] then family, rule = "gem", "fallback" end
	local rarity = Theme.rarity(def.rarity or "Common")
	local spec = {family = family, rule = rule, modifier = modifier, rarity = def.rarity or "Common", rank = rarity.rank,
		gear = Theme.ICON_GEAR[kind or ""] == true, color = type(def.color) == "string" and def.color or "9FB4C8"}
	spec.halo = spec.rank >= 3
	spec.key = table.concat({family, modifier or "", spec.color, spec.rarity, spec.gear and "g" or ""}, "|")
	return spec
end
function Theme.shapeOf(def) return Theme.iconSpec(def).family end

-- Template cache (unparented icon trees, cloned per use). Phones keep fewer.
Theme.IconCache = {templates = {}, max = 160, compactMax = 72, compact = false, builds = 0, clones = 0, evictions = 0, tick = 0, count = 0}
function Theme.iconCacheCompact(compact) Theme.IconCache.compact = compact == true end
-- Live ViewportFrame previews (the atlas's 3D thumbnails) are bounded: only
-- icons at least ICON_VIEWPORT_MIN px wide may use one, at most ICON_VIEWPORTS
-- per page (phones fewer); everything else is the cached vector icon.
Theme.ICON_VIEWPORT_MIN = 56
Theme.ICON_VIEWPORTS = {desktop = 6, compact = 2}
function Theme.iconViewportAllowed(size, used, compact)
	local cap = if compact then Theme.ICON_VIEWPORTS.compact else Theme.ICON_VIEWPORTS.desktop
	return (tonumber(size) or 0) >= Theme.ICON_VIEWPORT_MIN and (tonumber(used) or 0) < cap
end
Theme.ICON_LAYER_MAX = 12

local function drawLayer(holder, L, tones, px, z)
	local tone = tones[L[6]] or tones.base
	local flags = L[8] or NO
	local f = make("Frame", holder, {Name = "Layer", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(L[1], L[2]), Size = UDim2.fromScale(L[3], L[4]),
		Rotation = L[5], BackgroundColor3 = C.white, BorderSizePixel = 0, Active = false, ZIndex = z})
	if L[7] and L[7] > 0 then make("UICorner", f, {CornerRadius = UDim.new(math.min(0.5, L[7]), 0)}) end
	if flags.ring then
		f.BackgroundTransparency = 1
		make("UIStroke", f, {Color = tone, Thickness = math.max(1, math.floor(px * flags.ring + 0.5))})
		return f
	end
	if flags.g then
		f.BackgroundColor3, f.BackgroundTransparency = C.white, flags.a or 0.5
		return f
	end
	if flags.soft then
		-- Glow halo: two concentric translucent discs (no images), brighter inside.
		local a = flags.a or 0.6
		f.BackgroundColor3, f.BackgroundTransparency = tone, a + (1 - a) * 0.55
		local inner = make("Frame", f, {Name = "Core", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.66, 0.66),
			BackgroundColor3 = tone, BackgroundTransparency = a, BorderSizePixel = 0, Active = false, ZIndex = z})
		make("UICorner", inner, {CornerRadius = UDim.new(0.5, 0)})
		return f
	end
	f.BackgroundTransparency = flags.a or 0
	make("UIGradient", f, {Name = "Light", Rotation = Theme.ICON_LIGHT - L[5], Color = ColorSequence.new(lighten(tone, 0.38), darken(tone, 0.36))})
	if flags.o then make("UIStroke", f, {Color = darken(tone, 0.68), Thickness = if px >= 40 then 1.5 else 1, Transparency = 0.1}) end
	return f
end
-- Builds a fresh icon tree (no cache).
function Theme.buildIcon(def, size, spec)
	spec = spec or Theme.iconSpec(def)
	local px = if typeof(size) == "UDim2" then size.X.Offset else (size or 32)
	local holder = make("Frame", nil, {Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = if typeof(size) == "UDim2" then size else UDim2.fromOffset(px, px), BackgroundTransparency = 1, Active = false})
	local tones = Theme.iconTones(def)
	local r = Theme.rarity(spec.rarity)
	tones.rarity = r.color
	local z = 1
	if spec.halo then
		-- Rarity halo (Rare and above): a soft disc in the rarity colour behind the art.
		local h = drawLayer(holder, halo(0.5, 0.52, 0.92, "rarity", if spec.rank >= 5 then 0.62 else 0.74), tones, px, z)
		h.Name = "RarityHalo"
	end
	if spec.modifier then
		-- Compressed block behind the art; Radiant adds a glow and a spark.
		local back = drawLayer(holder, box(0.5, 0.54, 0.84, 0.8, "deep", 0.18, 0, {o = true, a = 0.25}), tones, px, z)
		back.Name = "Compressed"
		drawLayer(holder, box(0.5, 0.54, 0.7, 0.66, "base", 0.16, 0, {a = 0.6}), tones, px, z).Name = "CompressedFace"
		if spec.modifier == "radiant" then drawLayer(holder, halo(0.5, 0.5, 1, "glow", 0.45), tones, px, z).Name = "Radiance" end
	end
	local art = make("Frame", holder, {Name = "Art", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(if spec.modifier then 0.8 else 1, if spec.modifier then 0.8 else 1), BackgroundTransparency = 1, Active = false})
	for _, L in ipairs(Theme.ICON_MOTIFS[spec.family]) do drawLayer(art, L, tones, px * (if spec.modifier then 0.8 else 1), z) end
	if spec.modifier then
		drawLayer(holder, box(0.84, 0.16, 0.2, 0.2, if spec.modifier == "radiant" then "gold" else "lite", 0.1, 45), tones, px, z).Name = "CompressedBadge"
		if spec.modifier == "radiant" then drawLayer(holder, disc(0.84, 0.16, 0.08, "white", NO), tones, px, z).Name = "Spark" end
	end
	if spec.gear and spec.rank >= 2 then
		-- Gear: a rarity gem in the top-right corner (the rarity frame's jewel).
		drawLayer(holder, box(0.86, 0.14, 0.15, 0.15, "rarity", 0.1, 45), tones, px, z).Name = "RarityGem"
	end
	local veil = make("Frame", holder, {Name = "Veil", BackgroundColor3 = C.void, BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0,
		Visible = false, Active = false})
	Theme.corner(veil, 4)
	holder:SetAttribute("Shape", spec.family)
	return holder
end
-- Draws the icon for `def` into `parent` (size: UDim2 or px): a clone of the
-- cached template for that spec and size (built once).
function Theme.icon(parent, def, size)
	local spec = Theme.iconSpec(def)
	local px = if typeof(size) == "UDim2" then size.X.Offset .. "x" .. size.Y.Offset else tostring(size or 32)
	local cache = Theme.IconCache
	local key = spec.key .. "@" .. px
	local entry = cache.templates[key]
	cache.tick += 1
	if not entry then
		entry = {template = Theme.buildIcon(def, size, spec), used = cache.tick}
		cache.templates[key] = entry
		cache.builds += 1
		cache.count += 1
		local max = if cache.compact then cache.compactMax else cache.max
		while cache.count > max do
			local oldestKey, oldest = nil, math.huge
			for k, e in pairs(cache.templates) do if e ~= entry and e.used < oldest then oldestKey, oldest = k, e.used end end
			if not oldestKey then break end
			cache.templates[oldestKey].template:Destroy()
			cache.templates[oldestKey] = nil
			cache.count -= 1
			cache.evictions += 1
		end
	else
		cache.clones += 1
	end
	entry.used = cache.tick
	local icon = entry.template:Clone()
	icon:SetAttribute("Shape", spec.family)
	icon:SetAttribute("IconKey", key)
	icon.Parent = parent
	return icon
end

------------------------------------------------------------------------------
-- Item slot: well + rarity border + pictogram + stack count + cooldown sweep.
-- Name it yourself; children: Well, Rarity (UIStroke), Icon, Count, Sweep,
-- Glow (hover / selected), Tag (corner tag, e.g. "E" for equipped), Key (hotkey).
------------------------------------------------------------------------------
function Theme.slot(parent, opts)
	opts = opts or {}
	local size = opts.size or 44
	local b = make("TextButton", parent, {Name = opts.name or "Slot", Text = "", AutoButtonColor = false, BackgroundColor3 = C.inset,
		BackgroundTransparency = opts.transparency or 0.05, BorderSizePixel = 0, Size = UDim2.fromOffset(size, size), Position = opts.position or UDim2.new(),
		LayoutOrder = opts.order or 0, Selectable = true})
	Theme.corner(b, 4)
	make("UIGradient", b, {Name = "Vignette", Rotation = 90, Color = ColorSequence.new(rgb("1C2633"), rgb("0A0E14"))})
	make("UIStroke", b, {Name = "Rarity", Color = Theme.rarity("Common").frameColor, Thickness = 2, Transparency = 0.6})
	local glow = make("Frame", b, {Name = "Glow", BackgroundColor3 = C.white, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Active = false, ZIndex = 2})
	Theme.corner(glow, 4)
	local sweep = make("Frame", b, {Name = "Sweep", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = C.void, BackgroundTransparency = 0.35, BorderSizePixel = 0, Active = false, ZIndex = 4, Visible = false})
	Theme.corner(sweep, 4)
	Theme.label(b, {Name = "Count", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -3, 1, -2), Size = UDim2.fromOffset(size - 4, 12),
		Font = Theme.font.number, TextSize = if size < 44 then 8 else 10, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0, TextStrokeColor3 = C.void, Text = "", ZIndex = 5, TextTruncate = Enum.TextTruncate.None})
	local tag = Theme.label(b, {Name = "Tag", Position = UDim2.fromOffset(2, 2), Size = UDim2.fromOffset(13, 13), BackgroundTransparency = 0, BackgroundColor3 = C.gold,
		Font = Theme.font.heading, TextSize = 10, TextColor3 = C.onGold, TextXAlignment = Enum.TextXAlignment.Center, Text = "E", Visible = false, ZIndex = 5})
	Theme.corner(tag, 3)
	if opts.key then
		Theme.label(b, {Name = "Key", Position = UDim2.fromOffset(3, 2), Size = UDim2.fromOffset(12, 10), Font = Theme.font.number, TextSize = 8,
			TextColor3 = C.dim, Text = tostring(opts.key), ZIndex = 5})
	end
	return b
end
-- Fills a slot. data: {id, def, count, equipped, locked, selected, cooldown (0..1), placeholder}.
-- The pictogram is rebuilt only when the item changes (ItemId attribute).
function Theme.setSlot(b, data)
	data = data or {}
	local def = data.def
	local id = if def then data.id or def.id or "" else ""
	if b:GetAttribute("ItemId") ~= id then
		b:SetAttribute("ItemId", id)
		local old = b:FindFirstChild("Icon")
		if old then old:Destroy() end
		if def then
			local px = b.Size.X.Offset
			local icon = Theme.icon(b, def, math.floor(px * 0.72))
			icon.ZIndex = 3
		end
	end
	local r = Theme.rarity(def and def.rarity or "Common")
	local stroke = b:FindFirstChild("Rarity")
	stroke.Color = if def then r.frameColor else C.line
	stroke.Transparency = if not def then 0.5 elseif r.rank <= 1 then 0.45 else 0.05
	local count = data.count or 0
	b:FindFirstChild("Count").Text = if def and count > 1 then Theme.shortCount(count) else ""
	b:FindFirstChild("Tag").Visible = data.equipped == true
	b:FindFirstChild("Glow").BackgroundTransparency = if data.selected then 0.86 else 1
	local icon = b:FindFirstChild("Icon")
	local veil = icon and icon:FindFirstChild("Veil")
	if veil then veil.Visible = data.locked == true end
	local cd = math.clamp(tonumber(data.cooldown) or 0, 0, 1)
	b:FindFirstChild("Sweep").Visible = cd > 0
	b:FindFirstChild("Sweep").Size = UDim2.fromScale(1, cd)
end
function Theme.shortCount(n)
	n = math.floor(tonumber(n) or 0)
	if n >= 1e6 then return (string.format("%.1fM", n / 1e6):gsub("%.0M", "M")) end
	if n >= 1e4 then return math.floor(n / 1000) .. "k" end
	return tostring(n)
end
function Theme.commas(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local neg = s:sub(1, 1) == "-"
	if neg then s = s:sub(2) end
	s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return (if neg then "-" else "") .. s
end
-- (gsub returns two values; callers only ever see the string.)

------------------------------------------------------------------------------
-- Buttons, tabs and bars
------------------------------------------------------------------------------
local TONES = {
	primary = {bg = "F7C548", text = "2A1A04", hi = "FFF0B8", lo = "8A5A10"},
	secondary = {bg = "223042", text = "F3EEE2", hi = "F0CE82", lo = "3E2C15"},
	danger = {bg = "3A1A1A", text = "FF9A8C", hi = "FF8A7A", lo = "5A1A12"},
	selected = {bg = "1F4A44", text = "BFFFF0", hi = "6FE3C8", lo = "174038"},
	ghost = {bg = "111822", text = "A9B4C0", hi = "6E7A88", lo = "1A2431"},
}
function Theme.tone(b, tone)
	local t = TONES[tone] or TONES.secondary
	b.BackgroundColor3, b.TextColor3 = rgb(t.bg), rgb(t.text)
	local rim = b:FindFirstChild("Rim")
	if rim then rim:FindFirstChildOfClass("UIGradient").Color = ColorSequence.new(rgb(t.hi), rgb(t.lo)) end
	b:SetAttribute("Tone", tone)
end
-- opts: name, position, size, anchor, tone, textSize, order.
function Theme.button(parent, caption, opts)
	opts = opts or {}
	local b = make("TextButton", parent, {Name = opts.name or (tostring(caption) .. "Button"), Text = caption, AutoButtonColor = false, BorderSizePixel = 0,
		Font = Theme.font.label, TextSize = opts.textSize or Theme.text.label, Position = opts.position or UDim2.new(), Size = opts.size or UDim2.fromOffset(96, 34),
		AnchorPoint = opts.anchor or Vector2.zero, LayoutOrder = opts.order or 0, TextTruncate = Enum.TextTruncate.AtEnd, Selectable = true})
	Theme.corner(b, 5)
	Theme.sheen(b, 1, 0.78)
	Theme.rim(b, 1.5)
	Theme.tone(b, opts.tone or "secondary")
	return b
end
-- A row of tabs (segmented control). Returns {name → button}.
function Theme.tabs(parent, names, selected, onPick, opts)
	opts = opts or {}
	local row = make("Frame", parent, {Name = opts.name or "Tabs", BackgroundColor3 = C.void, BackgroundTransparency = 0.35, BorderSizePixel = 0,
		Position = opts.position or UDim2.new(), Size = opts.size or UDim2.new(1, 0, 0, 32)})
	Theme.corner(row, 5)
	make("UIStroke", row, {Color = C.line, Thickness = 1})
	make("UIListLayout", row, {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center})
	make("UIPadding", row, {PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3)})
	local buttons = {}
	for i, name in ipairs(names) do
		local b = Theme.button(row, name, {name = "Tab" .. name, order = i, size = UDim2.new(1 / #names, -3, 1, -6), textSize = opts.textSize or 12})
		b.Activated:Connect(function() if onPick then onPick(name) end end)
		buttons[name] = b
	end
	Theme.selectTab(buttons, selected)
	return buttons, row
end
function Theme.selectTab(buttons, selected)
	for name, b in pairs(buttons) do Theme.tone(b, if name == selected then "primary" else "ghost") end
end
-- Progress bar: sunken track, gradient fill with gloss, centred caption.
function Theme.bar(parent, opts)
	opts = opts or {}
	local height = opts.height or 14
	local color = opts.color or C.xp
	local track = make("Frame", parent, {Name = opts.name or "Bar", BackgroundColor3 = C.void, BackgroundTransparency = 0.1, BorderSizePixel = 0,
		Position = opts.position or UDim2.new(), Size = opts.size or UDim2.new(1, 0, 0, height), AnchorPoint = opts.anchor or Vector2.zero})
	Theme.corner(track, 3)
	make("UIStroke", track, {Color = C.frameLo, Thickness = 1})
	local fill = make("Frame", track, {Name = "Fill", BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1)})
	Theme.corner(fill, 3)
	make("UIGradient", fill, {Rotation = 90, Color = ColorSequence.new(lighten(color, 0.35), darken(color, 0.25))})
	make("Frame", fill, {Name = "Gloss", BackgroundColor3 = C.white, BackgroundTransparency = 0.78, BorderSizePixel = 0, Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 0.38, 0)})
	Theme.label(track, {Name = "Caption", Text = "", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.font.label,
		TextSize = opts.textSize or math.max(10, height - 3), TextStrokeTransparency = 0.25, TextStrokeColor3 = C.void, ZIndex = 2})
	return track
end
function Theme.setBar(track, fraction, caption)
	fraction = math.clamp(tonumber(fraction) or 0, 0, 1)
	if fraction ~= fraction then fraction = 0 end
	local fill = track:FindFirstChild("Fill")
	fill.Size = UDim2.fromScale(fraction, 1)
	fill.Visible = fraction > 0
	if caption ~= nil then track:FindFirstChild("Caption").Text = caption end
end

------------------------------------------------------------------------------
-- Tooltip: a lore card sized to its lines (pooled labels, one per line).
------------------------------------------------------------------------------
function Theme.tooltip(parent)
	local tip = Theme.frame(parent, {name = "Tooltip", size = UDim2.fromOffset(250, 60), transparency = 0.04, ornate = false, rimThickness = 1.5, zIndex = 50})
	tip.Visible = false
	tip.AutomaticSize = Enum.AutomaticSize.Y
	local list = tip:FindFirstChild("Body")
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.Size = UDim2.new(1, 0, 0, 0)
	make("UIListLayout", list, {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1)})
	make("UIPadding", list, {PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)})
	return tip
end
-- lines: Theme.lore output. at: Vector2 anchor point on screen; screen: Vector2.
function Theme.showTooltip(tip, lines, at, screen)
	local list = tip:FindFirstChild("Body")
	local pool = {}
	for _, child in ipairs(list:GetChildren()) do if child:IsA("TextLabel") then pool[child.LayoutOrder] = child end end
	local height = 16
	for i, line in ipairs(lines) do
		local l = pool[i]
		if not l then
			l = Theme.label(list, {Name = "Line" .. i, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 15), RichText = true, TextWrapped = true,
				TextTruncate = Enum.TextTruncate.None, ZIndex = 51, AutomaticSize = Enum.AutomaticSize.Y})
		end
		l.Visible = true
		l.Text = line.text
		l.TextColor3 = rgb(line.color or Theme.hex.dim)
		l.Font = if line.title then Theme.font.heading elseif line.bold then Theme.font.label else Theme.font.body
		l.TextSize = if line.title then 15 elseif line.blank then 6 else 12
		l.Size = UDim2.new(1, 0, 0, if line.blank then 6 elseif line.title then 18 else 15)
		height += if line.blank then 7 elseif line.title then 19 else 16 + 15 * math.floor(#(line.text:gsub("<[^>]+>", "")) / 40)
	end
	for i, l in pairs(pool) do if i > #lines then l.Visible = false end end
	local width = 250
	screen = screen or Vector2.new(1366, 768)
	at = at or Vector2.new(0, 0)
	local x = math.clamp(at.X + 16, 4, math.max(4, screen.X - width - 4))
	if at.X + 16 + width > screen.X then x = math.max(4, at.X - width - 12) end
	local y = math.clamp(at.Y, 4, math.max(4, screen.Y - height - 4))
	tip.Position = UDim2.fromOffset(x, y)
	tip.Size = UDim2.fromOffset(width, 0)
	tip.Visible = true
	tip:SetAttribute("EstimatedHeight", height)
	return x, y, width, height
end

------------------------------------------------------------------------------
-- Item lore (pure): SkyBlock-style tooltip lines for an item definition.
-- ctx: {Data, count, equipped, levels = {Skill = level}, enchants = {id = level},
--       bagged (accessory in the bag), examine (OSRS examine text first)}.
-- Each line: {text, color (hex), title?, bold?, blank?, kind}.
------------------------------------------------------------------------------
local STAT_FALLBACK = {damage = {"Damage", "FF5555"}, damagePercent = {"Damage", "FF5555", true}, lifesteal = {"Lifesteal", "FF5555", true},
	magicalPower = {"Magical Power", "FFAA00"}}
local function escape(text) return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end
Theme.escape = escape
function Theme.kindLabel(def)
	if type(def) ~= "table" then return "ITEM" end
	local kind = def.kind
	if kind == "weapon" then return if def.style == "ranged" then "BOW" elseif def.style == "magic" then "STAFF" else "SWORD" end
	if kind == "armor" then return ({helmet = "HELMET", chest = "CHESTPLATE", legs = "LEGGINGS", boots = "BOOTS"})[def.slot] or "ARMOR" end
	if kind == "tool" then return string.upper(def.toolKind or "TOOL") end
	if kind == "consumable" then return if def.category == "potion" then "POTION" elseif def.category == "buff" then "FEAST" else "FOOD" end
	if def.category == "ammo" then return "ARROWS" end
	if kind == "accessory" then return "ACCESSORY" end
	if kind == "pet" then return "PET" end
	if kind == "resource" then return "RESOURCE" end
	return "MATERIAL"
end
function Theme.lore(def, ctx)
	ctx = ctx or {}
	local Data = ctx.Data
	local lines = {}
	local function add(text, color, extra)
		local line = {text = text, color = color}
		for k, v in pairs(extra or {}) do line[k] = v end
		table.insert(lines, line)
		return line
	end
	if type(def) ~= "table" then
		add("Unknown item", Theme.hex.ember, {title = true, kind = "name"})
		return lines
	end
	local rarity = Theme.rarity(def.rarity)
	add(escape(def.name or def.id or "Item") .. (if (ctx.count or 0) > 1 then " <font color=\"#A9B4C0\">x" .. Theme.commas(ctx.count) .. "</font>" else ""),
		rarity.hex, {title = true, kind = "name"})
	local sub = string.lower(Theme.kindLabel(def))
	add(sub:sub(1, 1):upper() .. sub:sub(2) .. (if def.tier then "  ·  Tier " .. def.tier else ""), Theme.hex.faint, {kind = "kind"})
	local stats = type(def.stats) == "table" and def.stats or nil
	if stats and next(stats) then
		add("", nil, {blank = true})
		local order = (Data and Data.StatOrder) or {}
		local seen = {}
		local keys = {}
		for _, k in ipairs({"damage", "damagePercent"}) do if stats[k] then table.insert(keys, k); seen[k] = true end end
		for _, k in ipairs(order) do if stats[k] and not seen[k] then table.insert(keys, k); seen[k] = true end end
		local rest = {}
		for k in pairs(stats) do if not seen[k] then table.insert(rest, k) end end
		table.sort(rest)
		for _, k in ipairs(rest) do table.insert(keys, k) end
		for _, k in ipairs(keys) do
			local v = tonumber(stats[k])
			if v and v ~= 0 then
				local sdef = Data and Data.Stats and Data.Stats[k]
				local name = if sdef then sdef.name else (STAT_FALLBACK[k] and STAT_FALLBACK[k][1] or k)
				local percent = if sdef then sdef.percent else (STAT_FALLBACK[k] and STAT_FALLBACK[k][3])
				local good = if k == "damage" or k == "strength" or k == "critDamage" or k == "critChance" or k == "damagePercent" then "FF5555" else "55FF55"
				add(escape(name) .. ": <font color=\"#" .. good .. "\">" .. (if v > 0 then "+" else "") .. Theme.commas(v) .. (if percent then "%" else "") .. "</font>",
					Theme.hex.dim, {kind = "stat", stat = k})
			end
		end
	end
	if type(def.heal) == "number" then add("Restores <font color=\"#FF5555\">" .. def.heal .. " ❤ Health</font>" .. (if def.recovery then ", " .. def.recovery .. "s recovery" else ""), Theme.hex.dim, {kind = "stat"}) end
	if type(def.buff) == "table" and type(def.buff.stats) == "table" then
		local parts = {}
		for k, v in pairs(def.buff.stats) do
			local sdef = Data and Data.Stats and Data.Stats[k]
			table.insert(parts, "+" .. v .. " " .. (if sdef then sdef.name else k))
		end
		table.sort(parts)
		add("Buff: <font color=\"#55FF55\">" .. escape(table.concat(parts, ", ")) .. "</font> for " .. math.floor((def.buff.duration or 0) / 60) .. " min", Theme.hex.dim, {kind = "stat"})
	end
	local enchants = type(ctx.enchants) == "table" and ctx.enchants or nil
	if enchants and next(enchants) then
		local parts = {}
		for id, level in pairs(enchants) do
			local e = Data and Data.Enchants and Data.Enchants[id]
			table.insert(parts, (if e then e.name else id) .. " " .. tostring(level))
		end
		table.sort(parts)
		add("", nil, {blank = true})
		add(escape(table.concat(parts, ", ")), "8C9BFF", {kind = "enchant"})
	end
	local ability = def.ability
	if type(ability) == "table" and type(ability.text) == "string" then
		add("", nil, {blank = true})
		add("Ability: " .. escape(ability.name or "Surge") .. "  <font color=\"#F7C548\"><b>RIGHT CLICK</b></font>", Theme.hex.gold, {kind = "ability", bold = true})
		add(escape(ability.text), Theme.hex.dim, {kind = "ability"})
	end
	if type(def.description) == "string" and def.description ~= "" then
		add("", nil, {blank = true})
		add(escape(def.description), Theme.hex.faint, {kind = "description"})
	end
	if type(def.requires) == "table" and next(def.requires) then
		local parts, unmet = {}, false
		for skill, need in pairs(def.requires) do
			if type(need) == "number" then
				local have = ctx.levels and tonumber(ctx.levels[skill]) or 0
				if have < need then unmet = true end
				table.insert(parts, skill .. " " .. need)
			end
		end
		table.sort(parts)
		if #parts > 0 then add("Requires " .. escape(table.concat(parts, ", ")), if unmet then Theme.hex.ember else Theme.hex.faint, {kind = "requires", unmet = unmet}) end
	end
	if ctx.equipped then add("Currently equipped", Theme.hex.mint, {kind = "state"}) end
	if ctx.bagged then add("In your accessory bag", Theme.hex.mint, {kind = "state"}) end
	-- SkyBlock footer (§34): the bold RARITY TYPE line, the sell price, then the
	-- yellow click prompt (the satchel's left-click action; ctx.click = false
	-- hides it, a string replaces it).
	add("", nil, {blank = true})
	add("<b>" .. string.upper(def.rarity or "Common") .. " " .. Theme.kindLabel(def) .. "</b>", rarity.hex, {kind = "rarity", bold = true})
	if tonumber(def.value) then add("Sell price: <font color=\"#F7C548\">" .. Theme.commas(def.value) .. " coins</font>" .. (if (ctx.count or 0) > 1 then " each" else ""), Theme.hex.faint, {kind = "value"}) end
	-- Market price (§33 IslePriceCheckLocal text, passed in by the caller).
	if type(ctx.price) == "string" and ctx.price ~= "" then add("Market: <font color=\"#F7C548\">" .. escape(ctx.price) .. "</font>", Theme.hex.faint, {kind = "price"}) end
	local click = Theme.clickPrompt(def, ctx)
	if click then add(click, Theme.hex.prompt, {kind = "click", bold = true}) end
	return lines
end
-- The yellow click line for an item: ctx.click (string) or the first context
-- option's verb ("Click to wield!"), plus "Right-click for options." when more exist.
Theme.CLICK_WORDS = {Wield = "wield", Equip = "equip", Unequip = "unequip", Eat = "eat", Drink = "drink", Use = "use", Hotbar = "move it to your hotbar"}
function Theme.clickPrompt(def, ctx)
	ctx = ctx or {}
	if ctx.click == false then return nil end
	if type(ctx.click) == "string" then return ctx.click end
	if type(def) ~= "table" or type(def.id) ~= "string" then return nil end
	local options = Theme.itemActions(def, ctx)
	local first = options[1]
	if not first then return nil end
	local word = Theme.CLICK_WORDS[first.id]
	if first.id == "Use" and def.kind == "pet" then word = "adopt" end
	if first.id == "Use" and (def.kind == "resource" or def.kind == "material") then word = "view its collection" end
	if first.id == "Unequip" and def.kind == "accessory" then word = "remove it" end
	if not word then return "Right-click for options!" end
	return "Click to " .. word .. "!" .. (if #options > 1 then "  Right-click for options." else "")
end
-- OSRS examine text: the description, or a short line from the kind.
function Theme.examine(def)
	if type(def) ~= "table" then return "Nothing interesting happens." end
	if type(def.description) == "string" and def.description ~= "" then return def.name .. ": " .. def.description end
	return def.name .. ": a " .. string.lower(Theme.kindLabel(def)) .. "."
end

------------------------------------------------------------------------------
-- Context menu (pure): the options for an item, each mapped to an existing
-- server verb (or a local action). ctx: {count, equipped, bagged, canAdopt, upgraded}.
-- Option: {id, label, verb?, arg?, local?, confirm?, danger?}
--   Wield/Equip → equip "<id>" (Unequip → unequip "<slot>")
--   Eat/Drink   → consume "<id>"      Use (pet) → petAdopt "<id>"
--   Equip (accessory) → accessory "<id>" (toggles the bag)
--   Sell        → sell "<id>" (whole stack, merchant price; not while equipped; always confirms)
--   Sell…       → local "sellQty": the quantity picker (sell "<id>:<n>"), when 2+ can be sold
--   Drop        → drop "<id>" (whole stack, confirm; §29)
--   Move to hotbar → local (ReplicatedStorage.HotbarApi "assign")
--   Examine     → local (examine text toast)
------------------------------------------------------------------------------
Theme.GEAR_SLOTS = {weapon = true, helmet = true, chest = true, legs = true, boots = true, ammo = true}
function Theme.itemActions(def, ctx)
	ctx = ctx or {}
	local out = {}
	if type(def) ~= "table" or type(def.id) ~= "string" then return out end
	local id = def.id
	local function add(o) table.insert(out, o) end
	if def.kind == "weapon" or (def.slot and Theme.GEAR_SLOTS[def.slot] and def.kind ~= "tool") then
		if ctx.equipped then add({id = "Unequip", label = "Unequip", verb = "unequip", arg = def.slot})
		else add({id = if def.kind == "weapon" then "Wield" else "Equip", label = if def.kind == "weapon" then "Wield" else "Equip", verb = "equip", arg = id}) end
	elseif def.kind == "consumable" then
		local drink = def.category == "potion" or def.category == "buff"
		add({id = if drink then "Drink" else "Eat", label = if drink then "Drink" else "Eat", verb = "consume", arg = id})
	elseif def.kind == "accessory" then
		add({id = if ctx.bagged then "Unequip" else "Equip", label = if ctx.bagged then "Remove from bag" else "Equip", verb = "accessory", arg = id})
	elseif def.kind == "pet" then
		add({id = "Use", label = "Use (adopt)", verb = "petAdopt", arg = id})
	elseif def.kind == "resource" or def.kind == "material" then
		add({id = "Use", label = "Use", ["local"] = "use"})
	end
	add({id = "Hotbar", label = "Move to hotbar", ["local"] = "hotbar"})
	add({id = "Examine", label = "Examine", ["local"] = "examine"})
	if not ctx.equipped and not ctx.bagged then
		-- Sell always confirms (as the atlas does); with upgrades (reforge, stars,
		-- tome, enchantments) the server keeps the upgraded copy (§29 last-copy rule):
		-- spares say "spares", and the last upgraded copy offers neither verb, only
		-- an explanation (the server would refuse both).
		local count = ctx.count or 1
		if ctx.upgraded == true and count <= 1 then
			add({id = "Kept", label = "Upgraded: kept", ["local"] = "kept"})
		elseif ctx.upgraded == true then
			add({id = "Sell", label = "Sell " .. (count - 1) .. " spare" .. (if count > 2 then "s" else ""), verb = "sell", arg = id, confirm = true, upgraded = true})
			if count > 2 then add({id = "SellQty", label = "Sell…", ["local"] = "sellQty", max = count - 1}) end
			add({id = "Drop", label = "Drop spares", verb = "drop", arg = id, confirm = true, danger = true, upgraded = true})
		else
			add({id = "Sell", label = "Sell" .. (if count > 1 then " all" else ""), verb = "sell", arg = id, confirm = true, upgraded = false})
			if count > 1 then add({id = "SellQty", label = "Sell…", ["local"] = "sellQty", max = count}) end
			add({id = "Drop", label = "Drop", verb = "drop", arg = id, confirm = true, danger = true, upgraded = false})
		end
	end
	return out
end

------------------------------------------------------------------------------
-- Sorting (pure): ids sorted by mode ("rarity" | "name" | "kind" | "value").
------------------------------------------------------------------------------
Theme.SORTS = {"rarity", "name", "kind", "value"}
local KIND_RANK = {weapon = 1, armor = 2, tool = 3, accessory = 4, consumable = 5, pet = 6, resource = 7, material = 8}
function Theme.sortItems(ids, Items, mode)
	local function def(id) return Items[id] or {} end
	table.sort(ids, function(a, b)
		local da, db = def(a), def(b)
		local ra, rb = Theme.rarity(da.rarity).rank, Theme.rarity(db.rarity).rank
		if mode == "name" then return tostring(da.name or a) < tostring(db.name or b) end
		if mode == "value" then
			if (da.value or 0) ~= (db.value or 0) then return (da.value or 0) > (db.value or 0) end
		elseif mode == "kind" then
			local ka, kb = KIND_RANK[da.kind] or 9, KIND_RANK[db.kind] or 9
			if ka ~= kb then return ka < kb end
		end
		if ra ~= rb then return ra > rb end
		return tostring(da.name or a) < tostring(db.name or b)
	end)
	return ids
end

------------------------------------------------------------------------------
-- HUD lanes (pure). Every HUD script places itself from this one table so the
-- pieces never collide (verify-ui.luau checks it at 1366x768, 844x390 and
-- 730x303). The bottom centre belongs to the 9-slot hotbar (hotbar.client.lua):
-- slot 52 px (46 on short screens), gap 4, 6 px from the bottom, with a 70 px
-- band above it for the action bar and toasts.
-- opts: {touch, satchelOpen, satchelWidth}
------------------------------------------------------------------------------
Theme.HOTBAR = {count = 9, slot = 52, slotCompact = 46, gap = 4, bottom = 6, reserve = 70}
function Theme.hudLayout(w, h, opts)
	opts = opts or {}
	local short = h < 520
	local tiny = h < 340
	local touch = opts.touch == true or short
	local L = {w = w, h = h, short = short, tiny = tiny, touch = touch, edge = 10}
	local HB = Theme.HOTBAR
	local slot = if short then HB.slotCompact else HB.slot
	local hbw = HB.count * slot + (HB.count - 1) * HB.gap
	L.hotbar = {x = math.floor((w - hbw) / 2), y = h - HB.bottom - slot, w = hbw, h = slot, slot = slot}
	L.band = {x = L.hotbar.x, y = L.hotbar.y - HB.reserve, w = hbw, h = HB.reserve}
	-- Action bar: hotbar-wide on desktop; on short screens it narrows so the left
	-- column trackers (x <= 194) and the touch Attack column stay clear.
	local ah = if tiny then 20 elseif short then 26 else 30
	local aw = if short then math.min(hbw, w - 2 * 204) else hbw
	L.action = {x = math.floor((w - aw) / 2), y = L.hotbar.y - 6 - ah, w = aw, h = ah}
	-- Toasts sit on the band's top edge (bottom offset from the screen foot).
	L.toastBottom = h - L.band.y + 6
	-- Minimap: top-left. Desktop: map, info strip and a controls row below;
	-- touch / short: a 44 px controls column right of the map, info inside the map.
	local map = if tiny then 96 elseif short then 118 else 156
	L.map = {x = 10, y = 8, size = map}
	if touch then
		L.mapInfo = {x = 10, y = 8 + map - 22, w = map, h = 22, inside = true}
		L.mapControls = {x = 10 + map + 4, y = 8, w = 44, h = map, column = true}
		L.mapBlock = {x = 10, y = 8, w = map + 4 + 44, h = math.max(map, 92)}
	else
		L.mapInfo = {x = 10, y = 8 + map + 4, w = map, h = 26}
		L.mapControls = {x = 10, y = 8 + map + 4 + 26 + 4, w = map, h = 30}
		L.mapBlock = {x = 10, y = 8, w = map, h = map + 4 + 26 + 4 + 30}
	end
	-- Status orbs (overlay.client.lua, §34): Health, Prayer, Speed, Special beside
	-- the minimap. Desktop: a column of four 34 px orbs right of the map; touch:
	-- a 2 × 2 grid of 44 px orbs right of the controls column (touch floor).
	do
		local size, cols = if touch then 44 else 34, if touch then 2 else 1
		local x = if touch then L.mapControls.x + L.mapControls.w + 6 else L.map.x + map + 6
		local rows = math.ceil(4 / cols)
		L.orbs = {x = x, y = 8, size = size, cols = cols, gap = 4, w = cols * size + (cols - 1) * 4, h = rows * size + (rows - 1) * 4}
	end
	L.leftTop = L.mapBlock.y + L.mapBlock.h + 6
	L.leftWidth = if short then 184 else 250
	-- Sidebar (top-right scoreboard) with its dock row of buttons.
	local sw = if short then 156 else 214
	local sh = if tiny then 112 elseif short then 150 elseif touch then 234 else 226
	L.sidebar = {x = w - 10 - sw, y = 8, w = sw, h = sh}
	L.rightTop = L.sidebar.y + L.sidebar.h + 6
	-- The satchel panel docks under the sidebar on desktop (pinned option); on
	-- short screens it opens as a centred modal.
	local satW = opts.satchelWidth or 360
	if short then
		local mh = math.min(h - 16, 360)
		L.satchel = {x = math.floor((w - 420) / 2), y = math.floor((h - mh) / 2), w = 420, h = mh, modal = true}
	else
		L.satchel = {x = w - 10 - satW, y = L.rightTop, w = satW, h = math.min(372, h - L.rightTop - 140), modal = false}
	end
	-- Right column (party / minigame / lair HUDs, world boss board): under the
	-- sidebar, stepping left of a docked satchel; rightWidth is its widest HUD.
	L.rightEdge = if opts.satchelOpen and not short then w - 10 - satW - 8 else w - 10
	L.rightWidth = if short then 100 else 220 -- the widest right-column HUD (phones fold theirs to 96–100 px)
	-- Top lane between the map block and the sidebar (target panel, banners).
	-- (It starts right of the status orbs, which sit right of the minimap block.)
	L.lane = {left = math.max(L.mapBlock.x + L.mapBlock.w, L.orbs.x + L.orbs.w) + 10, right = L.sidebar.x - 10}
	-- Action label (§34, OSRS "verb target / N more options"): the top of the top
	-- lane, left of the centred target / boss panel (≤ 420 px wide from y 10).
	-- Mouse only: w = 0 on touch layouts or when the lane is too narrow.
	local alw = math.min(360, math.floor(w / 2) - 218 - L.lane.left)
	L.actionLabel = {x = L.lane.left, y = 8, w = if alw >= 180 and not touch then alw else 0, h = 34}
	-- XP lane (hud.client.lua: OSRS XP drops and the skill progress toast): its
	-- own column left of the right column, from rightTop, clear of the left
	-- column. Phones: one row (toast | drops) under the Wayfinder toast slot;
	-- desktop: drops over the toast. A narrow window with a docked satchel moves
	-- the lane under the right column instead.
	local leftLimit = 10 + L.leftWidth + 8
	local xr = L.rightEdge - L.rightWidth - 8
	if tiny then
		-- The smallest phones: one compact toast ("+48 Mining", level bar) between
		-- the Wayfinder toast (ends y 139), the prayer / spell bars and the right
		-- column; the drops column folds into it.
		L.xpToast = {x = xr - 120, y = 140, w = 120, h = 36, compact = true}
		L.xpDrops = {x = xr, y = 140, w = 0, h = 0, lines = 0}
	elseif short then
		local dw, tw, th = 120, 190, 46
		L.xpDrops = {x = xr - dw, y = L.rightTop, w = dw, h = th, lines = 2}
		L.xpToast = {x = xr - dw - 6 - tw, y = L.rightTop, w = tw, h = th}
	else
		local dw, tw = 170, 230
		local x, y = xr, L.rightTop
		if xr - tw < leftLimit then x, y = L.rightEdge, L.rightTop + 192 end
		L.xpDrops = {x = x - dw, y = y, w = dw, h = 120, lines = 5}
		L.xpToast = {x = x - tw, y = y + 126, w = tw, h = 46}
	end
	-- Level-up banner (ui.client.lua): centred under the top lane on wide
	-- screens; on short screens it sits in the top lane between the left column
	-- and the XP toast, so it never covers the XP lane (phones: same row).
	if short then
		local x0 = math.max(L.lane.left, leftLimit)
		local x1 = L.xpToast.x - 6
		local bw = math.min(340, x1 - x0)
		L.levelBanner = {x = x0 + math.floor((x1 - x0 - bw) / 2), y = if tiny then 112 else 142, w = bw, h = 60, slim = true}
	else
		local bw = math.min(if w < 900 then 340 else 440, math.floor(w * 0.9))
		L.levelBanner = {x = math.floor((w - bw) / 2), y = 142, w = bw, h = 82, slim = false}
	end
	-- Chat: kept to the bottom-left on desktop, clear of the hotbar and under the
	-- left column (tutorial 66 + lap 70 + traps 30 with their gaps: 176 px).
	-- §34: the chat filter tabs (All / Game / Public / Private / Crew / Trade) take
	-- the lane's top row and the docked window sits under them. Touch layouts keep
	-- Roblox's chat position, so the tab row is desktop-only (w = 0 on touch).
	local chatTop = math.max(h - 300, L.leftTop + 176 + 6)
	local chatW = math.max(0, L.hotbar.x - 24)
	L.chatTabs = {x = 10, y = chatTop, w = if touch then 0 else math.min(chatW, 6 * 64 + 5 * 3), h = 26, gap = 3}
	L.chat = {x = 10, y = chatTop + 30, w = chatW, h = math.max(0, h - 10 - chatTop - 30)}
	-- §34: the item pickup feed ("+3 Copperstone Ore"). Tall screens: under the
	-- XP toast in the XP lane (up to five 20 px lines, clear of the hotbar band);
	-- short screens: two 18 px lines (150 px) at the right edge above the touch Attack
	-- button (78 px, 4 px from the foot).
	if short then
		local fh = 2 * 18
		L.pickupFeed = {x = w - 10 - 150, y = h - 4 - 78 - 6 - fh, w = 150, h = fh, lines = 2, row = 18}
	else
		local y = L.xpToast.y + L.xpToast.h + 6
		local lines = math.clamp(math.floor((L.band.y - 8 - y) / 20), 0, 5)
		L.pickupFeed = {x = L.xpToast.x, y = y, w = L.xpToast.w, h = lines * 20, lines = lines, row = 20}
		if lines < 2 then
			-- No room under the toast (a narrow window with a docked satchel): the
			-- feed takes the column left of the XP lane, level with the drops.
			local right = math.min(L.xpDrops.x, L.xpToast.x) - 8
			local x = math.max(leftLimit, right - 220)
			local n = math.clamp(math.floor((L.band.y - 8 - L.xpDrops.y) / 20), 0, 5)
			L.pickupFeed = {x = x, y = L.xpDrops.y, w = right - x, h = n * 20, lines = n, row = 20}
		end
	end
	-- §43 Tutorial coach cards (tutorial.client.lua). Tall screens: a docked card
	-- right of the left column, under the level-up banner, left of the XP lane and
	-- pickup feed, above the chat lane and the announcement toast (never over the
	-- hotbar or the action bar); collapsed, it keeps only its 44 px header row.
	-- Short screens: the card opens as a centred modal (like the phone satchel)
	-- that ends above the action bar; collapsed it is a 44 px chip at the top of
	-- the left column (it steps aside while the lap / trap trackers show there).
	if short then
		-- Between the status orbs and the sidebar, so the minimap, orbs and sidebar
		-- stay readable; above the hotbar band (action bar, spell bar, notices).
		local floorY = L.band.y - 6
		local x0, x1 = L.orbs.x + L.orbs.w + 6, L.sidebar.x - 6
		local mw = math.min(400, x1 - x0)
		local mh = math.min(188, floorY - 8)
		L.coach = {x = x0 + math.floor((x1 - x0 - mw) / 2), y = math.max(8, math.floor((floorY - mh) / 2)), w = mw, h = mh, modal = true}
		L.coachChip = {x = 10, y = L.leftTop, w = L.leftWidth, h = 44}
	else
		local x = leftLimit
		local y = math.max(L.leftTop, L.levelBanner.y + L.levelBanner.h + 6)
		local right = math.min(L.xpDrops.x, L.xpToast.x) - 8
		if L.pickupFeed.lines > 0 then right = math.min(right, L.pickupFeed.x - 8) end
		local cw = math.max(0, math.min(360, right - x))
		local bottom = L.band.y - 64 - 54 - 6 -- the §31 announcement toast's top edge
		if x < L.chat.x + L.chat.w then bottom = math.min(bottom, L.chatTabs.y - 6) end
		L.coach = {x = x, y = y, w = cw, h = math.max(0, math.min(176, bottom - y)), modal = false}
		L.coachChip = {x = x, y = y, w = cw, h = 44}
		if cw < 260 or L.coach.h < 150 then
			-- A docked satchel pulls the XP lane into that space (narrow windows):
			-- the card opens centred above the action bar instead, chip as above.
			local floorY = L.band.y - 6
			local right = if opts.satchelOpen then L.satchel.x - 8 else w - 10
			local mw, mh = math.min(400, right - x), math.min(188, floorY - 8)
			L.coach = {x = x + math.floor((right - x - mw) / 2), y = math.max(8, floorY - mh), w = mw, h = mh, modal = true}
			L.coachChip = {x = x, y = y, w = math.max(cw, 0), h = 44}
		end
	end
	-- §46 heart ability chip (hearts.client.lua). Desktop: right of the hotbar,
	-- clear of the chat lane (bottom-left) and of the spell bar's corner
	-- (up to 360 px at the bottom right); when that corner would reach it, the
	-- chip sits above the action bar's right end instead. Touch: a 44 px chip
	-- above the band's left edge, lifted over the spell / prayer bars that
	-- combat.client.lua publishes as IsleHudLift (opts.lift).
	do
		local size = if touch then 44 else 40
		if touch then
			local lift = math.clamp(tonumber(opts.lift) or 0, 0, 200)
			local y = math.min(L.band.y - size - 6, h - 44 - lift - size - 6)
			L.heartChip = {x = L.band.x, y = math.max(8, y), w = size, h = size}
		else
			local x = L.hotbar.x + L.hotbar.w + 10
			if x + size <= w - 10 - 360 - 8 then
				L.heartChip = {x = x, y = L.hotbar.y + math.floor((L.hotbar.h - size) / 2), w = size, h = size}
			else
				L.heartChip = {x = L.action.x + L.action.w - size, y = L.action.y - 6 - size, w = size, h = size}
			end
		end
	end
	-- §49 QC L8: the Runebinding pouch chip (runes.client.lua). Desktop: above
	-- the action bar's left end (the heart chip owns the right of the hotbar or
	-- the action bar's right end); touch: the heart chip's row, from the band's
	-- right end, lifted over the spell / prayer bars like the heart chip.
	do
		local ph = 26
		if touch then
			local hc = L.heartChip
			local pw = math.max(0, math.min(200, L.band.x + L.band.w - (hc.x + hc.w + 6)))
			L.pouchChip = {x = L.band.x + L.band.w - pw, y = hc.y + math.floor((hc.h - ph) / 2), w = pw, h = ph}
		else
			local pw = math.min(220, math.floor(L.action.w / 2) - 8)
			L.pouchChip = {x = L.action.x, y = L.action.y - 6 - ph, w = math.max(0, pw), h = ph}
		end
	end
	-- §51 QC M9: the ship HUD (sailing.client.lua, only while aboard): centred
	-- on top of the bottom stack (action bar, heart and pouch chips), its button
	-- row inside the panel; compact on touch / short screens.
	do
		local top = math.min(L.action.y, L.heartChip.y, L.pouchChip.y) - 8
		if touch then
			-- Phones: a slim strip between the minimap block and the sidebar, above the chips.
			local left = if L.mapBlock then L.mapBlock.x + L.mapBlock.w + 4 else 10
			local right = if L.sidebar then L.sidebar.x - 4 else w - 10
			local sw, sh = math.max(0, math.min(316, right - left)), 88
			local x = math.clamp(math.floor((w - sw) / 2), left, math.max(left, right - sw))
			-- Lifted chips (spell / prayer bars) squeeze it down to the status orbs.
			local o = L.orbs
			local floorY = if o and o.x < x + sw and x < o.x + o.w then o.y + o.h + 4 else 8
			local y = math.max(floorY, top - sh)
			L.shipHud = {x = x, y = y, w = sw, h = math.max(56, top - y), compact = true}
		else
			local sw = math.min(420, w - 2 * 10)
			L.shipHud = {x = math.floor((w - sw) / 2), y = math.max(8, top - 168), w = sw, h = 168, compact = false}
		end
	end
	return L
end
-- Reduced motion: Settings › Reduced motion (IsleSettingReducedMotion) or the
-- device's own setting (GuiService.ReducedMotionEnabled, where available).
-- XP drops and banners then appear in place instead of tweening.
function Theme.reducedMotion(player)
	if player and player:GetAttribute("IsleSettingReducedMotion") == true then return true end
	local ok, on = pcall(function() return game:GetService("GuiService").ReducedMotionEnabled end)
	return ok and on == true
end
-- The hotbar team's STYLE table (hotbar.client.lua) in this theme's colours.
function Theme.hotbarStyle()
	local HB = Theme.HOTBAR
	return {
		slot = HB.slot, slotCompact = HB.slotCompact, gap = HB.gap, bottom = HB.bottom, reserve = HB.reserve, radius = 4, pad = 4,
		deep = C.inset, raised = C.raised, ivory = C.text, gold = C.gold, brass = C.frame, mint = C.mint, track = C.void,
		selected = C.gold, auto = C.mint, font = Theme.font.heading, countFont = Theme.font.number,
		glyphSize = 22, countSize = 10, keySize = 8, nameSize = 15,
	}
end

------------------------------------------------------------------------------
-- Isle clock (pure): date / season / time of day from Data.calendarAt.
------------------------------------------------------------------------------
local function ordinal(n)
	local tens = n % 100
	local suffix = if tens >= 11 and tens <= 13 then "th" else ({"st", "nd", "rd"})[n % 10] or "th"
	return n .. suffix
end
Theme.ordinal = ordinal
function Theme.isleClock(t, Data)
	if not Data or type(Data.calendarAt) ~= "function" then return nil end
	local ok, cal = pcall(Data.calendarAt, t)
	if not ok or type(cal) ~= "table" then return nil end
	local season = Data.SeasonById and Data.SeasonById[cal.season] or {}
	local dayLength = Data.Calendar and Data.Calendar.dayLength or 9150
	local minutes = math.floor((t - cal.dayStart) / dayLength * 1440) % 1440
	local hour, minute = minutes // 60, (minutes % 60) // 10 * 10
	local h12 = hour % 12
	if h12 == 0 then h12 = 12 end
	return {
		year = cal.year, season = cal.season, seasonName = season.name or cal.season, seasonColor = season.color or "F3EEE2", day = cal.day,
		date = (season.name or cal.season) .. " " .. ordinal(cal.day), clock = string.format("%d:%02d%s", h12, minute, if hour < 12 then "am" else "pm"),
		night = hour < 6 or hour >= 19, event = cal.event,
	}
end

------------------------------------------------------------------------------
-- World map (warp map tiles): island layout from world.server.lua (X/Z studs),
-- each tile's region (Data.Regions id) and its warp. travel = "recall" (the
-- recall charm verb, Hub/Home) or "guide" (Wayfinder waypoint to the island's
-- skyway beacon / entrance; region warps happen at the beacons in the world).
-- u / v / size place the illustrated tile on the Sky Chart (0..1 of the canvas,
-- px at full scale); x / z / r are the world layout the minimap tints use.
------------------------------------------------------------------------------
Theme.WorldMap = {
	bounds = {minX = -640, maxX = 940, minZ = -720, maxZ = 560},
	islands = {
		{id = "Hub", u = 0.42, v = 0.5, size = 150, name = "Compass Quay", region = "Hub", x = 0, z = 0, r = 115, top = "9DAA85", travel = "recall", target = "Hub"},
		{id = "SkywayTerrace", u = 0.42, v = 0.82, size = 100, name = "Guild Terrace", region = "Hub", x = 0, z = 232, r = 75, top = "A7B08A", travel = "guide", specs = {"anchor:Waypoint_Skyway"}},
		{id = "WardenReach", u = 0.42, v = 0.2, size = 95, name = "Warden Reach", region = "Hub", x = 0, z = -230, r = 70, top = "7C8498", travel = "guide", specs = {"region:Hub"}},
		{id = "Meadow", u = 0.24, v = 0.48, size = 100, name = "Mosswake Grove", region = "Meadow", x = -230, z = 0, r = 72, top = "8DB86E", travel = "guide", specs = {"region:Meadow", "warp:Meadow"}},
		{id = "MeadowReach", u = 0.24, v = 0.8, size = 95, name = "Meadow Reach", region = "Meadow", x = -230, z = 185, r = 70, top = "8DB86E", travel = "guide", specs = {"anchor:Waypoint_Entrance_Meadow", "region:Meadow"}},
		{id = "Quarry", u = 0.6, v = 0.48, size = 100, name = "Brassfall Quarry", region = "Quarry", x = 230, z = 0, r = 74, top = "9C9682", travel = "guide", specs = {"region:Quarry", "warp:Quarry"}},
		{id = "CinderShelf", u = 0.6, v = 0.2, size = 85, name = "Cinder Shelf", region = "Quarry", x = 230, z = -185, r = 58, top = "8F8676", travel = "guide", specs = {"anchor:Waypoint_Entrance_CinderShelf", "region:Quarry"}},
		{id = "Skyreach", u = 0.76, v = 0.64, size = 95, name = "Skyreach Heights", region = "Skyreach", x = 430, z = 110, r = 66, top = "96ACAB", travel = "guide", specs = {"warp:Skyreach", "region:Skyreach"}},
		{id = "Windpine", u = 0.08, v = 0.28, size = 110, name = "Windpine Grove", region = "Windpine", x = -500, z = -160, r = 85, top = "6B8E5A", travel = "guide", specs = {"warp:Windpine", "region:Windpine"}},
		{id = "Gloomhollow", u = 0.75, v = 0.18, size = 105, name = "Gloomhollow Caverns", region = "Gloomhollow", x = 440, z = -440, r = 82, top = "5B4F7A", travel = "guide", specs = {"warp:Gloomhollow", "region:Gloomhollow"}},
		{id = "Tidewater", u = 0.08, v = 0.74, size = 115, name = "Tidewater Shoals", region = "Tidewater", x = -520, z = 440, r = 92, top = "4FB0C6", travel = "guide", specs = {"warp:Tidewater", "region:Tidewater"}},
		{id = "Tempest", u = 0.89, v = 0.42, size = 95, name = "Tempest Spire", region = "Tempest", x = 600, z = -220, r = 70, top = "6F7FA8", travel = "guide", specs = {"warp:Tempest", "region:Tempest"}},
		{id = "ShatteredCrown", u = 0.92, v = 0.13, size = 115, name = "The Shattered Crown", region = "ShatteredCrown", x = 820, z = -600, r = 96, top = "B48CFF", travel = "guide", specs = {"warp:ShatteredCrown", "region:ShatteredCrown"}},
	},
	home = {id = "Home", u = 0.92, v = 0.86, size = 80, name = "Your Isle", region = "Home", travel = "recall", target = "Home", top = "7FA86A"},
}
-- Tile rectangle (0..1 of the map canvas) for an island.
function Theme.mapPoint(island)
	local b = Theme.WorldMap.bounds
	return (island.x - b.minX) / (b.maxX - b.minX), (island.z - b.minZ) / (b.maxZ - b.minZ)
end

------------------------------------------------------------------------------
-- Map art (§32, shared/MapArt.lua): tokens for the Sky Chart's 3D miniature
-- archipelago and the minimap's island plates. Added only; nothing above is
-- renamed. A bright day sky, cool stone, saturated foliage and a warm sun.
------------------------------------------------------------------------------
Theme.MapArt = {
	-- Sky Chart backdrop (top → horizon) and its cloud layers.
	skyTop = "4F8FD0", skyMid = "93C3EA", skyLow = "E3EFF7", cloud = "FFFFFF", cloudShade = "C9DBEA", haze = "F4F8FB",
	-- Miniature lighting (ViewportFrame Ambient / LightColor / LightDirection).
	ambient = "9AA4B8", sun = "FFF0D4", sunDirection = {-0.45, -1, -0.55},
	-- Island names: the theme's pixel display face, white with a heavy dark outline.
	labelFont = Theme.font.display, labelSize = 12, labelSizeCompact = 12, labelInk = "FFFFFF", labelOutline = "10151C",
	-- Warp points: a violet aether gem with a soft glow, a light pillar and a ground pad.
	warp = "7B4DFF", warpHi = "F0E6FF", warpGlow = "B48CFF", warpPad = "D9C8FF",
	-- Hover halo, the player's marker, locked-island wash and the requirement chip.
	halo = "FFE6A6", you = "6FE3C8", youInk = "05080C", lockWash = "7E8796", lockChip = "FF6B5A",
	-- Insets for the instanced isles (home, crew haven).
	insetFrame = "F0CE82", insetBack = "1A3550",
	-- Minimap plates: sea, cliff shadow and rim, water, paths, foliage, roofs, icons.
	sea = "173452", seaLow = "0D2238", shadow = "06101A", rim = "3E4856", water = "4FB6D8", waterDeep = "2D7FAE",
	path = "E2D3AC", bridge = "8B6A4A", canopy = "3F7A45", roof = "B0533F", beacon = "B48CFF", landmark = "FFD86B",
	npc = "F7C548", quest = "FFE14D", station = "6FE3C8",
}

------------------------------------------------------------------------------
-- HUD depth tokens (§34: shared/HudDepth.lua, overlay.client.lua, combat hitsplats).
------------------------------------------------------------------------------
Theme.HudDepth = {
	-- Action label / context menu: verb ivory, objects cyan, townsfolk yellow,
	-- creatures gold (level coloured green → red), players white, "/ N more" dim.
	verb = "F3EEE2", object = "5FE0E8", npc = "F7E26B", monster = "FFE14D", player = "FFFFFF", more = "A9B4C0",
	met = "6FE3C8", unmet = "FF6B5A", menuHead = "F7C548",
	-- Status orbs: liquid colours and the orb glass.
	orbHealth = "E8413C", orbPrayer = "5EC8E6", orbSpeed = "F2D15C", orbSpecial = "B07CFF", orbGlass = "0B1017", orbLow = "FF6B5A",
	-- Chat: game line colours by kind.
	chatLevel = "F7C548", chatRare = "FF8CF0", chatWarn = "FF8A7A", chatDrop = "8EE05A", chatCoins = "FFE6A6", chatAnnounce = "6FE3C8", chatInfo = "C9D3DC",
	-- Hitsplats: damage red, crit amber, miss blue, heal green, resist grey.
	splatHit = "C8282C", splatHitEdge = "4E0A0C", splatCrit = "FF9A1F", splatCritEdge = "6A2A00", splatMiss = "3E78C8", splatMissEdge = "1C3A66",
	splatHeal = "3FBF5A", splatHurt = "D2452E", splatResist = "7A858C", splatWeak = "FFD24A",
}

return Theme
