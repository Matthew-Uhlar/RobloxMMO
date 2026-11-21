--!nocheck
-- Aether Isles UI theme ("Skyforge"): one shared visual language for every
-- client script (atlas, HUD, satchel, hotbar, Wayfinder, combat HUD).
-- ReplicatedStorage.AetherUiTheme. See docs/DEPTH-CONTRACT.md §29.
--
--   Tokens     Theme.hex / Theme.color (palette), Theme.font, Theme.text (type
--              scale), Theme.space, Theme.rarity(rarity) → {hex, color, rank}
--   Components Theme.frame (ornate 9-slice panel), Theme.slot / Theme.setSlot
--              (item slot: icon + rarity border + stack count + cooldown sweep),
--              Theme.icon (item pictogram built from frames), Theme.tooltip /
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
	onGold = "2A1A04",
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
-- Item pictograms: original icons drawn from rotated frames in the item's own
-- colour with a dark outline. Shape by slot / kind / category.
------------------------------------------------------------------------------
local function lighten(color, amount) return color:Lerp(C.white, amount) end
local function darken(color, amount) return color:Lerp(C.black, amount) end
Theme.lighten, Theme.darken = lighten, darken
local function bit(parent, x, y, w, h, color, rotation, round)
	local f = make("Frame", parent, {Name = "Px", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h),
		BackgroundColor3 = color, BorderSizePixel = 0, Rotation = rotation or 0, Active = false})
	make("UIStroke", f, {Color = darken(color, 0.72), Thickness = 1, Transparency = 0.15})
	if round then make("UICorner", f, {CornerRadius = UDim.new(round, 0)}) end
	return f
end
function Theme.shapeOf(def)
	if type(def) ~= "table" then return "gem" end
	local kind, slot, cat = def.kind, def.slot, def.category
	if kind == "weapon" then
		if def.style == "ranged" then return "bow" end
		if def.style == "magic" then return "staff" end
		return "sword"
	end
	if kind == "armor" then return ({helmet = "helmet", chest = "chest", legs = "legs", boots = "boots"})[slot] or "chest" end
	if kind == "tool" then return ({Pickaxe = "pickaxe", Hatchet = "hatchet", Rod = "rod", Hoe = "hoe"})[def.toolKind] or "pickaxe" end
	if kind == "consumable" then return if cat == "potion" or cat == "buff" then "potion" else "food" end
	if cat == "ammo" then return "arrow" end
	if cat == "glyph" or cat == "tablet" then return "rune" end
	if kind == "accessory" then return "ring" end
	if kind == "pet" then return "paw" end
	if kind == "resource" then
		return ({Mining = "ore", Woodcutting = "log", Fishing = "fish", Farming = "crop"})[def.skill] or "ore"
	end
	return "gem"
end
local SHAPES = {
	sword = function(p, c) bit(p, .56, .44, .16, .66, lighten(c, .35), 45); bit(p, .34, .66, .38, .1, darken(c, .25), 45); bit(p, .24, .76, .1, .22, darken(c, .45), 45) end,
	bow = function(p, c) bit(p, .44, .5, .12, .78, c, 30, .5); bit(p, .6, .5, .03, .72, C.text, 30); bit(p, .62, .38, .36, .05, darken(c, .2), -50) end,
	staff = function(p, c) bit(p, .46, .58, .09, .74, darken(c, .35), 30); bit(p, .64, .24, .3, .3, lighten(c, .3), 45, .5) end,
	pickaxe = function(p, c) bit(p, .5, .58, .1, .72, rgb("8A5A32"), 35); bit(p, .6, .36, .7, .12, c, -40, .3) end,
	hatchet = function(p, c) bit(p, .46, .58, .1, .72, rgb("8A5A32"), 30); bit(p, .64, .32, .32, .3, c, 30) end,
	rod = function(p, c) bit(p, .48, .5, .07, .9, rgb("8A5A32"), 40); bit(p, .72, .68, .02, .5, C.text, 0); bit(p, .72, .9, .12, .12, c, 0, .5) end,
	hoe = function(p, c) bit(p, .46, .56, .1, .74, rgb("8A5A32"), 35); bit(p, .66, .26, .3, .14, c, -55) end,
	helmet = function(p, c) bit(p, .5, .46, .66, .5, c, 0, .45); bit(p, .5, .66, .66, .14, darken(c, .3), 0); bit(p, .5, .58, .1, .28, darken(c, .5), 0) end,
	chest = function(p, c) bit(p, .5, .55, .52, .62, c, 0, .12); bit(p, .24, .38, .2, .3, darken(c, .2), 0, .3); bit(p, .76, .38, .2, .3, darken(c, .2), 0, .3); bit(p, .5, .46, .08, .4, lighten(c, .3), 0) end,
	legs = function(p, c) bit(p, .5, .26, .58, .14, darken(c, .25), 0); bit(p, .36, .58, .22, .56, c, 0); bit(p, .64, .58, .22, .56, c, 0) end,
	boots = function(p, c) bit(p, .34, .44, .2, .44, c, 0); bit(p, .4, .7, .38, .16, darken(c, .2), 0, .4); bit(p, .66, .44, .2, .44, c, 0); bit(p, .72, .7, .38, .16, darken(c, .2), 0, .4) end,
	food = function(p, c) bit(p, .5, .5, .6, .44, c, -20, .5); bit(p, .26, .64, .22, .1, C.text, -20); bit(p, .6, .44, .2, .1, lighten(c, .4), -20, .5) end,
	potion = function(p, c) bit(p, .5, .62, .5, .5, c, 0, .5); bit(p, .5, .3, .2, .2, lighten(c, .55), 0); bit(p, .5, .18, .26, .08, rgb("8A5A32"), 0) end,
	arrow = function(p, c) bit(p, .5, .5, .06, .86, rgb("C9A879"), 45); bit(p, .76, .24, .18, .18, c, 45); bit(p, .26, .74, .16, .1, C.text, 45) end,
	rune = function(p, c) bit(p, .5, .5, .58, .7, darken(c, .35), 0, .2); bit(p, .5, .44, .3, .06, lighten(c, .5), 45); bit(p, .5, .44, .3, .06, lighten(c, .5), -45); bit(p, .5, .7, .26, .06, lighten(c, .5), 0) end,
	ring = function(p, c) local r = bit(p, .5, .58, .6, .6, darken(c, .2), 0, .5); r.BackgroundTransparency = 1; r:SetAttribute("Hollow", true); r:FindFirstChildOfClass("UIStroke").Thickness = 3; r:FindFirstChildOfClass("UIStroke").Color = c; bit(p, .5, .26, .26, .26, lighten(c, .4), 45) end,
	paw = function(p, c) bit(p, .5, .62, .44, .36, c, 0, .5); for i, x in ipairs({.26, .42, .58, .74}) do bit(p, x, if i == 1 or i == 4 then .38 else .26, .16, .18, lighten(c, .2), 0, .5) end end,
	ore = function(p, c) bit(p, .5, .58, .7, .5, rgb("5C5F66"), 12, .2); bit(p, .38, .52, .2, .2, lighten(c, .2), 45); bit(p, .62, .64, .16, .16, c, 45); bit(p, .6, .42, .12, .12, lighten(c, .5), 45) end,
	log = function(p, c) bit(p, .5, .5, .76, .38, darken(c, .1), -25, .3); bit(p, .82, .36, .2, .36, lighten(c, .35), -25, .5) end,
	fish = function(p, c) bit(p, .46, .5, .58, .34, c, 0, .5); bit(p, .82, .5, .2, .3, darken(c, .2), 45); bit(p, .3, .44, .06, .06, C.void, 0, .5) end,
	crop = function(p, c) bit(p, .5, .62, .06, .6, rgb("4E8A3A"), 0); bit(p, .38, .36, .2, .3, c, -30, .5); bit(p, .62, .36, .2, .3, c, 30, .5); bit(p, .5, .22, .18, .26, lighten(c, .25), 0, .5) end,
	gem = function(p, c) bit(p, .5, .52, .5, .5, c, 45); bit(p, .42, .44, .14, .14, lighten(c, .6), 45) end,
}
-- Draws the pictogram for `def` into a new "Icon" frame (size: UDim2 or px).
function Theme.icon(parent, def, size)
	local holder = make("Frame", parent, {Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = if typeof(size) == "UDim2" then size else UDim2.fromOffset(size or 32, size or 32), BackgroundTransparency = 1, Active = false})
	local color = rgb(type(def) == "table" and type(def.color) == "string" and def.color or "C9D6E3")
	local shape = Theme.shapeOf(def)
	holder:SetAttribute("Shape", shape)
	SHAPES[shape](holder, color)
	return holder
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
	if icon then
		for _, px in ipairs(icon:GetChildren()) do
			if px:IsA("Frame") then px.BackgroundTransparency = if data.locked then 0.6 else (px:GetAttribute("Hollow") and 1 or 0) end
		end
	end
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
	if tonumber(def.value) then add("Sell value: <font color=\"#F7C548\">" .. Theme.commas(def.value) .. " coins</font>" .. (if (ctx.count or 0) > 1 then " each" else ""), Theme.hex.faint, {kind = "value"}) end
	add("", nil, {blank = true})
	add("<b>" .. string.upper(def.rarity or "Common") .. " " .. Theme.kindLabel(def) .. "</b>", rarity.hex, {kind = "rarity", bold = true})
	return lines
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
			add({id = "Drop", label = "Drop spares", verb = "drop", arg = id, confirm = true, danger = true, upgraded = true})
		else
			add({id = "Sell", label = "Sell" .. (if count > 1 then " all" else ""), verb = "sell", arg = id, confirm = true, upgraded = false})
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
	L.lane = {left = L.mapBlock.x + L.mapBlock.w + 10, right = L.sidebar.x - 10}
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
	local chatTop = math.max(h - 300, L.leftTop + 176 + 6)
	L.chat = {x = 10, y = chatTop, w = math.max(0, L.hotbar.x - 24), h = math.max(0, h - 10 - chatTop)}
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

return Theme
