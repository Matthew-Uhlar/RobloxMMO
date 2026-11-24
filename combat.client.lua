-- Combat input, health bars and damage numbers. See docs/DEPTH-CONTRACT.md §5.
-- The server is authoritative: this script only picks a target, sends the verb
-- for the wielded style on IsleCombat and renders IsleCombatFx feedback.
--   melee  ("attack", model)            sword reach (14 studs)
--   ranged ("ranged", model)            bow reach (<= 40 studs), one arrow per shot
--   magic  ("cast", model|nil, spellId) autocast (or the best unlocked damage
--                                       spell), the spell bar quick-casts
-- The style, quiver and spell supplies come from the snapshot's depth.combat
-- (IsleUpdate pushes plus every snapshot the atlas accepts, re-fired locally on
-- ReplicatedStorage.IsleSnapshotLocal). Spell bar right-clicks set autocast
-- through the atlas (IsleActionLocal:Fire("autocast", id)); denied reasons
-- become atlas toasts (IsleToastLocal), with a floating fallback.
-- Spell bar layout: right-aligned above the action bar (touch: left of the
-- Attack button), hidden while building or talking. Its height is published as
-- the local IsleHudLift attribute so atlas toasts float above it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local combat = ReplicatedStorage:WaitForChild("IsleCombat")
local fx = ReplicatedStorage:WaitForChild("IsleCombatFx")

local ATTACK_RANGE = 14
local BASE_COOLDOWN = 0.45
local TARGET_DROP_RANGE = 80

-- Shared definitions (spells, weapons). Optional: without them every style
-- still attacks; only the spell bar and range details degrade.
local Data
do
	local module = ReplicatedStorage:WaitForChild("AetherData", 10)
	if module then
		local ok, value = pcall(require, module)
		if ok and type(value) == "table" then Data = value end
	end
end
local CS = Data and type(Data.CombatStyles) == "table" and Data.CombatStyles or nil
local MAX_RANGE = CS and tonumber(CS.maxRange) or 40

local function rgb(hex)
	hex = tostring(hex or "FFFFFF")
	return Color3.fromRGB(tonumber(hex:sub(1, 2), 16) or 255, tonumber(hex:sub(3, 4), 16) or 255, tonumber(hex:sub(5, 6), 16) or 255)
end
-- Palette and type match the atlas "Aether Brass" design system (ui.client.lua).
-- Colours, fonts and HUD lanes from the shared theme (§29).
local Theme = require(ReplicatedStorage:WaitForChild("AetherUiTheme"))
-- Hitsplat styles and overhead bar colours (§34, shared/HudDepth.lua).
local HD = require(ReplicatedStorage:WaitForChild("AetherHudDepth"))
local deep, ivory, gold, mint = Theme.color.inset, Theme.color.text, Theme.color.gold, Theme.color.mint
local brass, brassDark, track, ember, raised = Theme.color.frame, Theme.color.frameLo, Theme.color.void, Theme.color.ember, Theme.color.raised
local heavy, display = Enum.Font.BuilderSansExtraBold, Theme.font.display
local bold = heavy
local white = Color3.new(1, 1, 1)

local function make(class, parent, props)
	local object = Instance.new(class)
	for k, v in pairs(props or {}) do object[k] = v end
	object.Parent = parent
	return object
end
-- Rim with a light top edge (Border mode: on a TextLabel the Contextual
-- default would outline the text instead).
local function round(parent, radius, stroke)
	make("UICorner", parent, {CornerRadius = UDim.new(0, radius)})
	if stroke then
		local rim = make("UIStroke", parent, {Name = "Rim", Color = stroke, Thickness = 1.5, Transparency = 0.05, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
		make("UIGradient", rim, {Rotation = 90, Color = ColorSequence.new(white, Color3.new(0.5, 0.5, 0.5))})
		return rim
	end
	return nil
end
local function sheen(parent, bottom)
	make("UIGradient", parent, {Name = "Sheen", Rotation = 90, Color = ColorSequence.new(white, Color3.new(bottom, bottom, bottom))})
end

------------------------------------------------------------------------------
-- HUD (DisplayOrder below the atlas, which uses 8)
------------------------------------------------------------------------------
local gui = make("ScreenGui", player:WaitForChild("PlayerGui"), {
	Name = "IsleCombatHud", ResetOnSpawn = false, DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
local PANEL_HEIGHT = 58
-- Target panel: level medallion, name, boss timer chip and a gradient HP meter
-- (gloss + end cap). Bosses switch to ember rims and corner gems.
local panel = make("Frame", gui, {
	Name = "Target", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.fromOffset(300, PANEL_HEIGHT), BackgroundColor3 = deep, BackgroundTransparency = 0.06, Visible = false,
})
local panelRim = round(panel, 12, brass)
sheen(panel, 0.7)
make("UISizeConstraint", panel, {MaxSize = Vector2.new(420, 70)})
local ornaments = make("Frame", panel, {Name = "Ornaments", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false})
for _, c in ipairs({{0, 0}, {1, 0}, {0, 1}, {1, 1}}) do
	local gem = make("Frame", ornaments, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(c[1], if c[1] == 0 then 5 else -5, c[2], if c[2] == 0 then 5 else -5),
		Size = UDim2.fromOffset(6, 6), Rotation = 45, BackgroundColor3 = ember, BorderSizePixel = 0})
	make("UIStroke", gem, {Color = track, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
end
local medal = make("Frame", panel, {Name = "Level", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 9, 0.5, 0), Size = UDim2.fromOffset(40, 40),
	BackgroundColor3 = raised, BorderSizePixel = 0})
local medalRim = round(medal, 20, gold)
sheen(medal, 0.5)
local medalText = make("TextLabel", medal, {BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = display, TextSize = 16, TextColor3 = ivory,
	TextStrokeTransparency = 0.35, TextStrokeColor3 = deep, Text = ""})
local panelName = make("TextLabel", panel, {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(58, 6), Size = UDim2.new(1, -126, 0, 22),
	Font = heavy, TextSize = 16, TextColor3 = ivory, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = "",
})
local panelTimer = make("TextLabel", panel, {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 7), Size = UDim2.fromOffset(56, 20), BackgroundColor3 = track, BackgroundTransparency = 0.2,
	Font = heavy, TextSize = 13, TextColor3 = gold, Text = "", Visible = false,
})
round(panelTimer, 10, brass)
local barBack = make("Frame", panel, {
	Position = UDim2.fromOffset(58, 31), Size = UDim2.new(1, -70, 0, 17), BackgroundColor3 = track, BorderSizePixel = 0,
})
round(barBack, 8)
-- A visible track: the fill alone disappeared against the deep panel.
make("UIStroke", barBack, {Color = rgb("4C7680"), Thickness = 1, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
local barFill = make("Frame", barBack, {Size = UDim2.fromScale(1, 1), BackgroundColor3 = mint, BorderSizePixel = 0})
round(barFill, 8)
make("UIGradient", barFill, {Color = ColorSequence.new(Color3.new(0.6, 0.6, 0.6), white)})
local gloss = make("Frame", barFill, {BackgroundColor3 = white, BackgroundTransparency = 0.8, BorderSizePixel = 0, Position = UDim2.fromOffset(2, 1), Size = UDim2.new(1, -4, 0.42, 0)})
round(gloss, 6)
local barCap = make("Frame", barFill, {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -1, 0.5, 0), Size = UDim2.fromOffset(5, 13), BackgroundColor3 = white, BorderSizePixel = 0})
round(barCap, 3)
local barText = make("TextLabel", barBack, {
	BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = heavy, TextSize = 12,
	TextColor3 = ivory, TextStrokeTransparency = 0.3, TextStrokeColor3 = deep, Text = "", ZIndex = 2,
})
-- Event banner: a ribbon strip with brass end gems.
local banner = make("TextLabel", gui, {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 76), Size = UDim2.fromOffset(460, 34),
	BackgroundColor3 = deep, BackgroundTransparency = 0.06, Font = heavy, TextSize = 16, TextColor3 = gold,
	Text = "", Visible = false,
})
round(banner, 17, brass)
make("UISizeConstraint", banner, {MaxSize = Vector2.new(460, 40)})
for _, x in ipairs({0, 1}) do
	local gem = make("Frame", banner, {Name = "End", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, if x == 0 then 16 else -16, 0.5, 0), Size = UDim2.fromOffset(8, 8),
		Rotation = 45, BackgroundColor3 = gold, BorderSizePixel = 0})
	make("UIStroke", gem, {Color = brassDark, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
end
-- Layout (shared HUD map, kept in step with nav.client.lua and npc.client.lua):
--   atlas guild badge (ui.client.lua)  top-left      x 10-315, y 8-92
--   left column (x 10-260, from y 100): free; the old tutorial tracker is retired (Polish)
--   Wayfinder minimap (nav.client.lua) top-right     SIZE 118 (viewport < 520 tall) or 156,
--                                                    x W-10-SIZE..W-10, y 8..SIZE+42
--   top lane between them (x 325..W-SIZE-20): target/boss panel y 10-68,
--   event banner y 76-110, Wayfinder toast y 118-158.
-- Items centre on the screen when they fit the lane, else centre in the lane
-- (shrunk to it). Screens whose lane is under 220 px stack below the tracker.
local EDGE, BELOW_HUD = 10, 174
-- Theme.hudLayout for the current screen (the hotbar gap, minimap, sidebar).
local function lanes()
	local view = gui.AbsoluteSize
	local camera = Workspace.CurrentCamera
	local w = if view and view.X > 0 then view.X else 1280
	local h = if view and view.Y > 0 then view.Y elseif camera and camera.ViewportSize.Y > 0 then camera.ViewportSize.Y else 720
	return Theme.hudLayout(w, h, {touch = UserInputService.TouchEnabled, satchelOpen = player:GetAttribute("IsleSatchelOpen") == true})
end
-- The top lane runs between the minimap block (left) and the sidebar (right).
local function laneFor(width)
	local L = lanes()
	BELOW_HUD = L.leftTop
	return L.lane.left, L.lane.right
end
local function placeInLane(object, wanted, top, height, width)
	local left, right = laneFor(width)
	local w = wanted
	if width / 2 - w / 2 >= left and width / 2 + w / 2 <= right then
		object.AnchorPoint, object.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, top)
	elseif right - left >= 220 then
		w = math.min(w, right - left)
		object.AnchorPoint, object.Position = Vector2.new(0, 0), UDim2.new(0, left + math.floor((right - left - w) / 2), 0, top)
	else
		return false
	end
	object.Size = UDim2.fromOffset(w, height)
	return true
end
local layoutKey
local function layoutHud(isBoss)
	local view = gui.AbsoluteSize
	local width = if view and view.X > 0 then view.X else 1280
	local key = width .. "x" .. (if view then view.Y else 0) .. (if isBoss then "b" else "n")
	if key == layoutKey then return end
	layoutKey = key
	local panelWidth = if isBoss then 380 else 300
	if not placeInLane(panel, panelWidth, EDGE, PANEL_HEIGHT, width) or not placeInLane(banner, 460, 76, 34, width) then
		-- Very narrow: stack at the top of the left column.
		local _, right = laneFor(width)
		local w = math.max(160, math.min(panelWidth, right - EDGE))
		panel.AnchorPoint, panel.Position, panel.Size = Vector2.new(0, 0), UDim2.fromOffset(EDGE, BELOW_HUD), UDim2.fromOffset(w, PANEL_HEIGHT)
		banner.AnchorPoint, banner.Position = Vector2.new(0, 0), UDim2.fromOffset(EDGE, BELOW_HUD + PANEL_HEIGHT + 8)
		banner.Size = UDim2.fromOffset(math.max(160, math.min(460, right - EDGE)), 34)
	end
end
layoutHud(false)
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	layoutKey = nil
	layoutHud(false)
end)
local bannerToken = 0
local function showBanner(text, color)
	bannerToken += 1
	local token = bannerToken
	banner.Text, banner.TextColor3, banner.Visible = text, color or gold, true
	task.delay(4, function() if bannerToken == token then banner.Visible = false end end)
end

local attackButton -- created for touch devices
local STYLE_LOOK = {
	melee = {glyph = "⚔", caption = "ATTACK", color = "F3C66E", name = "Melee"},
	ranged = {glyph = "➶", caption = "SHOOT", color = "9BD67E", name = "Ranged"},
	magic = {glyph = "✦", caption = "CAST", color = "8FA8FF", name = "Magic"},
}
local function ensureAttackButton()
	if attackButton or not UserInputService.TouchEnabled then return end
	attackButton = make("TextButton", gui, {
		-- Bottom-right corner, right of the hotbar gap (§29 lanes).
		Name = "AttackButton", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -4),
		Size = UDim2.fromOffset(78, 78), BackgroundColor3 = raised, BackgroundTransparency = 0.05,
		Font = heavy, Text = "⚔", TextSize = 30, TextColor3 = gold, AutoButtonColor = true, TextYAlignment = Enum.TextYAlignment.Top,
	})
	round(attackButton, 39, gold)
	make("UIPadding", attackButton, {PaddingTop = UDim.new(0, 12)})
	-- Inner brass ring and an ATTACK caption under the crossed blades.
	local ring = make("Frame", attackButton, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -6), Size = UDim2.new(1, -10, 1, 2), BackgroundTransparency = 1})
	make("UICorner", ring, {CornerRadius = UDim.new(1, 0)})
	make("UIStroke", ring, {Color = brass, Thickness = 1, Transparency = 0.45, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
	make("TextLabel", attackButton, {Name = "Caption", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(60, 12),
		BackgroundTransparency = 1, Font = heavy, TextSize = 11, TextColor3 = ivory, Text = "ATTACK"})
	-- Quiver count (ranged): a small brass plate on the rim.
	local quiverTag = make("TextLabel", attackButton, {Name = "Quiver", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -8, 0, -2), Size = UDim2.fromOffset(38, 18),
		BackgroundColor3 = track, Font = heavy, TextSize = 11, TextColor3 = ivory, Text = "", Visible = false, BorderSizePixel = 0})
	round(quiverTag, 9, brass)
end
ensureAttackButton()

------------------------------------------------------------------------------
-- Loadout (snapshot depth.combat) and the spell bar
------------------------------------------------------------------------------
-- All spell-bar state lives in one table (keeps this chunk well under Luau's
-- 200-local limit).
local S = {
	loadout = {style = "melee", supplies = {}, levels = {}, ammoCount = 0},
	quiver = 0,           -- arrows in the quiver (snapshot, then QuiverCount pushes)
	slots = {},           -- spell ids on the bar, in slot order
	buttons = {},         -- slot TextButtons
	readyAt = {},         -- [spellId] = os.clock() when a utility spell is ready
	length = {},          -- [spellId] = that cooldown's length
	selected = 1,         -- gamepad cursor
	lastCast = nil,       -- {id, at} for rolling back a denied cast's cooldown
	swingLength = BASE_COOLDOWN,
	nextSwing = 0,
	deniedAt = 0,
}
local floatText -- defined with the damage numbers below
local function spellDef(id) return Data and type(Data.Spells) == "table" and type(id) == "string" and Data.Spells[id] or nil end
local function weaponDef()
	local id = S.loadout.weapon
	return Data and type(id) == "string" and type(Data.Items) == "table" and Data.Items[id] or nil
end
local function currentStyle()
	local style = S.loadout.style
	return if STYLE_LOOK[style] then style else "melee"
end
local function magicLevel() return tonumber(S.loadout.levels.Magic) or 1 end
local function unlocked(spell) return magicLevel() >= (tonumber(spell.level) or 1) end
local function mana() return tonumber(player:GetAttribute("Mana")) or 0 end
-- Glyphs a cast consumes: the spell's costs minus the wielded staff's elements.
local function glyphCost(spell)
	local free, out = {}, {}
	local weapon = weaponDef()
	if currentStyle() == "magic" and weapon and type(weapon.magic) == "table" and CS then
		for _, element in ipairs(weapon.magic.elements or {}) do
			local e = CS.elements and CS.elements[element]
			if e then free[e.glyph] = true end
		end
	end
	for id, n in pairs(type(spell.costs) == "table" and spell.costs or {}) do
		if not free[id] then out[id] = n end
	end
	return out
end
-- ok, reason (a "denied" reason) for casting right now (level, weapon, mana, glyphs).
local function affordable(spell)
	if not unlocked(spell) then return false, "level" end
	if spell.requiresWeapon and currentStyle() ~= "magic" then return false, "weapon" end
	if mana() < (tonumber(spell.mana) or 0) then return false, "mana" end
	for id, n in pairs(glyphCost(spell)) do
		if (tonumber(S.loadout.supplies[id]) or 0) < n then return false, "glyphs" end
	end
	return true, nil
end
-- Damage spells the player can cast, strongest (highest level) first.
local function damageSpells()
	local list = {}
	for _, id in ipairs(Data and type(Data.SpellOrder) == "table" and Data.SpellOrder or {}) do
		local spell = spellDef(id)
		if spell and spell.kind == "damage" and unlocked(spell) then table.insert(list, spell) end
	end
	table.sort(list, function(a, b) return (a.level or 0) > (b.level or 0) end)
	return list
end
-- The spell a plain attack casts: the saved autocast, else the strongest unlocked.
local function attackSpell()
	local auto = spellDef(S.loadout.autocast)
	if auto and auto.kind == "damage" and unlocked(auto) then return auto end
	return damageSpells()[1]
end
-- Bar contents: (magic) autocast + up to two more damage spells + Rootbind;
-- (any style) Mend once unlocked, Hubward while a tablet is in the satchel.
local SLOT_COUNT = 6
local function chooseSlots()
	local out = {}
	if not Data or type(Data.Spells) ~= "table" then return out end
	if currentStyle() == "magic" then
		local first = attackSpell()
		if first then table.insert(out, first.id) end
		for _, spell in ipairs(damageSpells()) do
			if #out >= 3 then break end
			if not table.find(out, spell.id) then table.insert(out, spell.id) end
		end
		local root = spellDef("Rootbind")
		if root and unlocked(root) then table.insert(out, root.id) end
	end
	local mend = spellDef("Mend")
	if mend and unlocked(mend) then table.insert(out, mend.id) end
	local hubward = spellDef("Hubward")
	if hubward and unlocked(hubward) and (tonumber(S.loadout.supplies.HubwardTablet) or 0) > 0 then table.insert(out, hubward.id) end
	while #out > SLOT_COUNT do table.remove(out) end
	return out
end

-- Spell bar: style chip (glyph + quiver/mana caption) and up to six slots.
local spellBar = make("Frame", gui, {Name = "SpellBar", AnchorPoint = Vector2.new(1, 1), BackgroundTransparency = 1, Size = UDim2.fromOffset(48, 48)})
local styleChip = make("Frame", spellBar, {Name = "StyleChip", BackgroundColor3 = deep, BackgroundTransparency = 0.06, BorderSizePixel = 0})
round(styleChip, 12, brass)
sheen(styleChip, 0.7)
local styleGlyph = make("TextLabel", styleChip, {Name = "Glyph", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, 0, 0.62, 0),
	Font = heavy, TextSize = 22, TextColor3 = gold, Text = "⚔", TextStrokeTransparency = 0.4, TextStrokeColor3 = deep})
local styleCaption = make("TextLabel", styleChip, {Name = "Caption", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -3),
	Size = UDim2.new(1, 0, 0, 13), Font = heavy, TextSize = 11, TextColor3 = ivory, Text = "MELEE"})
for i = 1, SLOT_COUNT do
	local b = make("TextButton", spellBar, {Name = "Spell" .. i, Text = "", AutoButtonColor = true, BackgroundColor3 = raised, BackgroundTransparency = 0.04,
		BorderSizePixel = 0, Visible = false, Selectable = true})
	local rim = round(b, 10, brass)
	if rim then rim.Name = "Rim" end
	sheen(b, 0.6)
	make("TextLabel", b, {Name = "Glyph", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 1), Size = UDim2.new(1, 0, 0.66, 0),
		Font = heavy, TextSize = 20, TextColor3 = white, Text = "", TextStrokeTransparency = 0.35, TextStrokeColor3 = deep, ZIndex = 2})
	make("TextLabel", b, {Name = "Cost", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 12),
		Font = heavy, TextSize = 11, TextColor3 = rgb("9FC3FF"), Text = "", ZIndex = 2})
	local key = make("TextLabel", b, {Name = "Key", AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(-3, -3), Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = gold, Font = heavy, TextSize = 10, TextColor3 = deep, Text = ({"Z", "X", "C", "V", "B", "N"})[i], BorderSizePixel = 0, ZIndex = 4,
		Visible = not UserInputService.TouchEnabled})
	make("UICorner", key, {CornerRadius = UDim.new(0, 4)})
	-- Cooldown sweep: a dark veil that drains downwards as the spell recovers.
	local sweep = make("Frame", b, {Name = "Sweep", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = track, BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 3})
	make("UICorner", sweep, {CornerRadius = UDim.new(0, 10)})
	make("Frame", b, {Name = "Veil", Size = UDim2.fromScale(1, 1), BackgroundColor3 = track, BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 3, Visible = false})
	local auto = make("TextLabel", b, {Name = "Auto", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 3, 0, -3), Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = mint, Font = heavy, TextSize = 9, TextColor3 = deep, Text = "A", BorderSizePixel = 0, ZIndex = 4, Visible = false})
	make("UICorner", auto, {CornerRadius = UDim.new(1, 0)})
	S.buttons[i] = b
end
-- Gamepad cursor ring.
local cursor = make("Frame", spellBar, {Name = "Cursor", BackgroundTransparency = 1, Visible = false, ZIndex = 5})
make("UICorner", cursor, {CornerRadius = UDim.new(0, 12)})
local cursorRing = make("UIStroke", cursor, {Color = mint, Thickness = 2, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})

local ELEMENT_GLYPH = {Gale = "≋", Tide = "≈", Stone = "◆", Ember = "▲"}
local KIND_GLYPH = {snare = "❦", heal = "✚", teleport = "⌂"}
local TIER_MARK = {Dart = "", Lance = "²", Cascade = "³"}
local function slotSize()
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize
	local height = if viewport and viewport.Y > 0 then viewport.Y else (gui.AbsoluteSize and gui.AbsoluteSize.Y or 720)
	return if height < 520 then 44 else 48 -- 44 px: the phone touch-target floor
end
local function hudLift(value)
	if player:GetAttribute("IsleHudLift") ~= value then player:SetAttribute("IsleHudLift", value) end
end
-- Hidden while the island builder runs (it owns the bottom) or a dialogue is open.
local dialogueBox
local function talking()
	if not dialogueBox or not dialogueBox.Parent then
		local guiRoot = player:FindFirstChild("PlayerGui")
		local folk = guiRoot and guiRoot:FindFirstChild("TownsfolkDialogue")
		dialogueBox = folk and folk:FindFirstChild("Dialogue")
	end
	return dialogueBox ~= nil and dialogueBox.Visible == true
end
local function layoutSpellBar()
	local size, gap = slotSize(), 4
	local n = #S.slots
	local width = size + n * (size + gap)
	spellBar.Size = UDim2.fromOffset(width, size)
	-- Touch: left of the Attack button (x W-88..W-10); else the bottom-right
	-- corner. When that would reach over the hotbar (phones), the bar centres in
	-- the band above the hotbar, just over the action bar (Theme.hudLayout).
	local L = lanes()
	local right = if attackButton then 96 else 10
	local lift0, centred = 44, false
	if L.w - right - width < L.hotbar.x + L.hotbar.w + 8 then lift0, centred = L.h - L.action.y + 4, true end
	S.spellLift0, S.spellCentred, S.spellRight = lift0, centred, right
	spellBar.AnchorPoint = if centred then Vector2.new(0.5, 1) else Vector2.new(1, 1)
	spellBar.Position = if centred then UDim2.new(0.5, 0, 1, -lift0) else UDim2.new(1, -right, 1, -lift0)
	styleChip.Size = UDim2.fromOffset(size, size)
	styleGlyph.TextSize = if size < 48 then 19 else 22
	styleCaption.TextSize = 11
	for i, b in ipairs(S.buttons) do
		b.Position = UDim2.fromOffset(size + gap + (i - 1) * (size + gap), 0)
		b.Size = UDim2.fromOffset(size, size)
		b.Visible = i <= n
	end
	cursor.Size = UDim2.fromOffset(size + 6, size + 6)
	local shown = player:GetAttribute("IslandBuilding") ~= true and not talking()
	spellBar.Visible = shown
	-- Prayer quick bar (Prayer section below) stacks above the spell bar.
	local lift = if shown then size + 6 + (S.spellLift0 - 44) else 0
	if S.prayerLayout then lift += S.prayerLayout(size, shown) end
	hudLift(lift)
end
-- Static slot faces (glyph, mana cost, autocast badge); dynamic state per frame.
local function paintSlots()
	S.slots = chooseSlots()
	for i, b in ipairs(S.buttons) do
		local spell = spellDef(S.slots[i])
		if spell then
			local glyph = b:FindFirstChild("Glyph")
			glyph.Text = (KIND_GLYPH[spell.kind] or ELEMENT_GLYPH[spell.element] or "✦") .. (TIER_MARK[spell.tier] or "")
			glyph.TextColor3 = rgb(spell.color)
			b:FindFirstChild("Cost").Text = if (spell.mana or 0) > 0 then tostring(spell.mana) else ""
			b:FindFirstChild("Auto").Visible = spell.id == S.loadout.autocast
			local rim = b:FindFirstChild("Rim")
			if rim then rim.Color = if spell.id == S.loadout.autocast then mint else brass end
		end
	end
	if S.selected > #S.slots then S.selected = math.max(1, #S.slots) end
	local style = currentStyle()
	local look = STYLE_LOOK[style]
	styleGlyph.Text, styleGlyph.TextColor3 = look.glyph, rgb(look.color)
	if attackButton then
		attackButton.Text, attackButton.TextColor3 = look.glyph, rgb(look.color)
		attackButton:FindFirstChild("Caption").Text = look.caption
	end
	layoutSpellBar()
end
-- Per-frame slot state: cooldown sweep, greyed when unaffordable, captions.
local function quiverText(n) return if n >= 1000 then string.format("%.1fk", n / 1000) else tostring(n) end
local function refreshSlots(now)
	local style = currentStyle()
	if style == "ranged" then
		styleCaption.Text, styleCaption.TextColor3 = "×" .. quiverText(S.quiver), if S.quiver > 0 then ivory else ember
	elseif style == "magic" then
		styleCaption.Text, styleCaption.TextColor3 = tostring(math.floor(mana())), rgb("9FC3FF")
	else
		styleCaption.Text, styleCaption.TextColor3 = "MELEE", ivory
	end
	if attackButton then
		local tag = attackButton:FindFirstChild("Quiver")
		tag.Visible = style == "ranged"
		tag.Text = "×" .. quiverText(S.quiver)
		tag.TextColor3 = if S.quiver > 0 then ivory else ember
	end
	for i, b in ipairs(S.buttons) do
		local spell = spellDef(S.slots[i])
		if spell and b.Visible then
			local ok = affordable(spell)
			local left, length = 0, 1
			if spell.cooldown and S.readyAt[spell.id] then
				left, length = S.readyAt[spell.id] - now, S.length[spell.id] or spell.cooldown
			elseif spell.kind == "damage" then
				left, length = S.nextSwing - now, S.swingLength
			end
			b:FindFirstChild("Sweep").Size = UDim2.fromScale(1, math.clamp(left / math.max(0.05, length), 0, 1))
			b:FindFirstChild("Veil").Visible = not ok
			b:FindFirstChild("Glyph").TextTransparency = if ok then 0 else 0.55
			b:FindFirstChild("Cost").TextColor3 = if mana() >= (spell.mana or 0) then rgb("9FC3FF") else ember
		end
	end
	local pad = UserInputService.GamepadEnabled and #S.slots > 0
	cursor.Visible = pad
	cursorRing.Transparency = if pad then 0 else 1
	if pad then
		local b = S.buttons[S.selected]
		cursor.Position = UDim2.fromOffset(b.Position.X.Offset - 3, -3)
	end
end

-- The island builder (build.client.lua) owns the bottom of the screen while it
-- runs (local IslandBuilding attribute): hide Attack so it never covers Done.
local function syncAttackButton()
	if attackButton then attackButton.Visible = player:GetAttribute("IslandBuilding") ~= true end
	layoutSpellBar()
end
player:GetAttributeChangedSignal("IslandBuilding"):Connect(syncAttackButton)
player:GetAttributeChangedSignal("IsleHotbarHeight"):Connect(layoutSpellBar) -- the hotbar appeared, resized or hid
syncAttackButton()
paintSlots()

------------------------------------------------------------------------------
-- Targeting
------------------------------------------------------------------------------
local target -- Model
local targetHighlight = make("Highlight", nil, {
	FillTransparency = 1, OutlineColor = gold, OutlineTransparency = 0.1, DepthMode = Enum.HighlightDepthMode.Occluded,
})
local function liveMonster(model)
	return model and model.Parent and CollectionService:HasTag(model, "IsleMonster") and not model:GetAttribute("Dead")
		and (model:GetAttribute("Health") or 1) > 0
end
local function canTarget(model)
	if not liveMonster(model) then return false end
	local owner = model:GetAttribute("OwnerUserId")
	return owner == nil or owner == player.UserId
end
local function rootOf()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart"), character and character:FindFirstChildOfClass("Humanoid")
end
local function distanceTo(model)
	local root = rootOf()
	local body = model and model.PrimaryPart
	if not root or not body then return math.huge end
	local radius = math.min(6, math.max(body.Size.X, body.Size.Z) / 2)
	return (root.Position - body.Position).Magnitude - radius
end
-- Reach of the wielded style: sword 14, bow its own reach, magic the full 40.
local function reach()
	local style = currentStyle()
	if style == "ranged" then
		local bow = weaponDef()
		return math.min(MAX_RANGE, bow and type(bow.ranged) == "table" and tonumber(bow.ranged.range) or MAX_RANGE)
	elseif style == "magic" then
		return MAX_RANGE
	end
	return ATTACK_RANGE
end
local function setTarget(model)
	if model == target then return end
	local old = target
	target = model
	-- §34: the target keeps its overhead bar; the old one lingers, then fades.
	if S.overhead then
		if old then S.overhead.touch(old) end
		if model then S.overhead.touch(model) end
	end
	-- Highlights live under the camera (adorned), so a server-side Destroy of the
	-- monster never takes the reusable highlight with it.
	targetHighlight.Adornee = model
	targetHighlight.Parent = if model then Workspace.CurrentCamera else nil
end
local function monsterFromPart(part)
	local node = part
	while node and node ~= Workspace do
		if node:IsA("Model") and CollectionService:HasTag(node, "IsleMonster") then return node end
		node = node.Parent
	end
	return nil
end
-- On screen (in front of the camera) for long-range auto-targeting.
local function inView(model)
	local camera = Workspace.CurrentCamera
	local body = model.PrimaryPart
	if not camera or not body or not camera.WorldToViewportPoint then return true end
	local point, visible = camera:WorldToViewportPoint(body.Position)
	return visible == true and point.Z > 0
end
-- Holding attack calls this every frame; the tag scan is cached for 0.2s.
-- Melee picks the nearest within sword reach; ranged/magic the nearest within
-- reach that is in view (gamepad and touch aim where the camera looks).
local SCAN_INTERVAL = 0.2
local scanAt, scanned = -math.huge, nil
local function nearestMonster(fresh, range)
	range = range or reach()
	local long = range > ATTACK_RANGE
	if canTarget(target) and distanceTo(target) <= range then return target end
	local now = os.clock()
	if not fresh and now - scanAt < SCAN_INTERVAL and (scanned == nil or canTarget(scanned)) and (scanned == nil or distanceTo(scanned) <= range) then return scanned end
	scanAt = now
	local best, bestDist = nil, range
	for _, model in ipairs(CollectionService:GetTagged("IsleMonster")) do
		if canTarget(model) then
			local d = distanceTo(model)
			if d <= bestDist and (not long or d <= ATTACK_RANGE or inView(model)) then best, bestDist = model, d end
		end
	end
	scanned = best
	return best
end

------------------------------------------------------------------------------
-- Swing feedback and denied notices
------------------------------------------------------------------------------
local attackSpeed = 0
local armBusy = false
local DENIED_TEXT = {
	style = "Your weapon can't do that", ammo = "Out of arrows", ammoTier = "These arrows are too heavy for your bow",
	sight = "No line of sight", range = "Out of range", mana = "Not enough mana", glyphs = "Out of glyphs",
	level = "Magic level too low", spell = "Choose a spell to cast", immune = "Bosses shrug off Rootbind",
	combat = "Can't teleport while in combat", teleport = "The tablet fizzles", target = "No target in range",
	leashing = "It's retreating — let it reset",
	-- Lairs: ordered sigils, a sealed boss, another party's fight.
	order = "Break the sigils in order: lowest number first", sealed = "Sealed! Break its sigils first", lair = "That fight is not yours",
}
local function deniedText(action, reason)
	if reason == "weapon" then
		return if action == "ranged" then "Equip a bow to shoot" elseif action == "cast" then "Equip a staff or wand to cast" else "Wrong weapon"
	end
	return DENIED_TEXT[reason]
end
-- Short toast: the atlas toast strip when it is running, else a floating line.
local function toast(text)
	if type(text) ~= "string" then return end
	local now = os.clock()
	if now - S.deniedAt < 0.6 and S.deniedText == text then return end
	S.deniedAt, S.deniedText = now, text
	local channel = ReplicatedStorage:FindFirstChild("IsleToastLocal")
	if channel and channel:IsA("BindableEvent") then
		channel:Fire(text)
		return
	end
	local root = rootOf()
	if root and floatText then floatText(root.Position + Vector3.new(0, 3.5, 0), text, rgb("FFB4A8"), 16) end
end
-- Gesture names (animate.client.lua): attack · shoot (bow) · cast (staff) · flick (wand) · heal.
local function gestureFor(style, spell)
	if spell and spell.kind == "heal" then return "heal" end
	if style == "ranged" then return "shoot" end
	if style == "magic" or spell then
		local weapon = weaponDef()
		local wand = weapon and type(weapon.magic) == "table" and #(weapon.magic.elements or {}) == 0
		return if wand then "flick" else "cast"
	end
	return "attack"
end
local function slash(style, spell)
	style = style or "melee"
	local root = rootOf()
	if not root then return end
	if style == "melee" and not spell then
		local part = make("Part", nil, {
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
			Material = Enum.Material.Neon, Color = ivory, Size = Vector3.new(5.5, 0.18, 0.5), Transparency = 0.15,
		})
		local side = if math.random() < 0.5 then 1 else -1
		local start = root.CFrame * CFrame.new(0, 0.6, -3.2) * CFrame.Angles(0, 0, math.rad(35 * side))
		part.CFrame = start * CFrame.Angles(0, math.rad(-40 * side), 0)
		part.Parent = Workspace.CurrentCamera
		TweenService:Create(part, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = start * CFrame.Angles(0, math.rad(40 * side), 0), Transparency = 1, Size = Vector3.new(6.5, 0.05, 0.3),
		}):Play()
		task.delay(0.25, function() part:Destroy() end)
	end
	-- Arm swing (local only): nudge the shoulder joint and restore it.
	local character = player.Character
	local shoulder = character and (character:FindFirstChild("RightShoulder", true) or character:FindFirstChild("Right Shoulder", true))
	-- [Animation] Route the swing through the shared gesture player (animate.client.lua) when it is running.
	local gesture = ReplicatedStorage:FindFirstChild("IsleGestureLocal")
	if gesture then
		local name = gestureFor(style, spell)
		gesture:Fire(name, if name == "heal" then nil else target, if name == "heal" then nil else S.loadout.weapon)
	elseif shoulder and shoulder:IsA("Motor6D") and not armBusy then
		armBusy = true
		local rest = shoulder.C0
		local swing = TweenService:Create(shoulder, TweenInfo.new(0.09, Enum.EasingStyle.Quad), {C0 = rest * CFrame.Angles(math.rad(110), 0, 0)})
		swing:Play()
		swing.Completed:Once(function()
			local back = TweenService:Create(shoulder, TweenInfo.new(0.14, Enum.EasingStyle.Quad), {C0 = rest})
			back:Play()
			back.Completed:Once(function() armBusy = false end)
		end)
	end
end
-- Seconds between attacks for the wielded weapon (the server enforces the real cooldown).
local function cooldown()
	local haste = 1 + math.clamp(attackSpeed, 0, 100) / 100
	local style, weapon = currentStyle(), weaponDef()
	if style == "ranged" and weapon and type(weapon.ranged) == "table" then
		return math.max(0.1, tonumber(weapon.ranged.speed) or 1) / haste
	elseif style == "magic" then
		return math.max(0.1, weapon and type(weapon.magic) == "table" and tonumber(weapon.magic.speed) or 1.2) / haste
	end
	return BASE_COOLDOWN / haste
end
local function alive()
	local _, humanoid = rootOf()
	return humanoid ~= nil and humanoid.Health > 0
end
-- Casts spellId (target: a monster for damage/snare spells, nil for self spells).
-- Returns true when the cast was sent.
local function castSpell(id, model)
	local spell = spellDef(id)
	if not spell or not alive() then return false end
	local ok, why = affordable(spell)
	if not ok then
		toast(deniedText("cast", why))
		return false
	end
	local now = os.clock()
	if spell.kind == "damage" or spell.kind == "snare" then
		local range = math.min(MAX_RANGE, tonumber(spell.range) or MAX_RANGE)
		if not (canTarget(model) and distanceTo(model) <= range) then model = nearestMonster(true, range) end
		if not model then
			toast(deniedText("cast", "target"))
			return false
		end
		setTarget(model)
		if spell.kind == "damage" and now < S.nextSwing then return false end
	else
		model = nil
	end
	if spell.cooldown and S.readyAt[id] and now < S.readyAt[id] then return false end
	if spell.kind == "damage" then
		S.swingLength = cooldown()
		S.nextSwing = now + S.swingLength
	end
	if spell.cooldown then
		S.readyAt[id], S.length[id] = now + spell.cooldown, spell.cooldown
	end
	S.lastCast = {id = id, at = now}
	combat:FireServer("cast", model, id)
	slash("magic", spell)
	return true
end
local function tryAttack(model)
	if not alive() then return false end
	if not canTarget(model) then return false end
	setTarget(model)
	local style = currentStyle()
	if distanceTo(model) > reach() then return false end
	local now = os.clock()
	if now < S.nextSwing then return false end
	if style == "magic" then
		local spell = attackSpell()
		if not spell then
			toast(deniedText("cast", "spell"))
			return false
		end
		return castSpell(spell.id, model)
	end
	if style == "ranged" and S.quiver < 1 then
		toast(deniedText("ranged", "ammo"))
		return false
	end
	S.swingLength = cooldown()
	S.nextSwing = now + S.swingLength
	combat:FireServer(if style == "ranged" then "ranged" else "attack", model)
	slash(style)
	return true
end
-- Spell bar slot i (keys Z X C V B N, taps, gamepad L1 on the cursor; 1-9 belong to the hotbar).
local function castSlot(i)
	local id = S.slots[i]
	if not id then return false end
	local spell = spellDef(id)
	local model = if spell and (spell.kind == "damage" or spell.kind == "snare") then target else nil
	return castSpell(id, model)
end
-- Right-click / long-press a damage slot: make it the autocast (saved server-side).
local function setAutocast(id)
	local spell = spellDef(id)
	if not spell or not spell.autocast then return end
	local channel = ReplicatedStorage:FindFirstChild("IsleActionLocal")
	if channel and channel:IsA("BindableEvent") then channel:Fire("autocast", id) end
end
for i, b in ipairs(S.buttons) do
	b.Activated:Connect(function() S.selected = i; castSlot(i) end)
	b.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then setAutocast(S.slots[i]) end
	end)
end

------------------------------------------------------------------------------
-- Input: click/tap a monster, touch button or ButtonR2 attack the nearest;
-- keys Z X C V B N cast spell slots, DPad cycles the cursor and L1 casts it.
------------------------------------------------------------------------------
-- Include-only filter: invisible guard walls, prompt parts and props can never
-- swallow a tap aimed at a monster (the server still validates range).
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
local function pick(screenPosition)
	local camera = Workspace.CurrentCamera
	if not camera then return nil end
	local monsters = CollectionService:GetTagged("IsleMonster")
	if #monsters == 0 then return nil end
	local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
	rayParams.FilterDescendantsInstances = monsters
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 300, rayParams)
	return hit and monsterFromPart(hit.Instance)
end
-- Number keys 1-9 belong to the hotbar (hotbar.client.lua); spells sit on the Z row.
local SLOT_KEYS = {[Enum.KeyCode.Z] = 1, [Enum.KeyCode.X] = 2, [Enum.KeyCode.C] = 3,
	[Enum.KeyCode.V] = 4, [Enum.KeyCode.B] = 5, [Enum.KeyCode.N] = 6}
local held = nil -- "mouse" | "button" | "pad"
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local model = pick(input.Position)
		if model then
			tryAttack(model)
			held = "mouse"
		end
	elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
		held = "pad"
		local model = nearestMonster(true)
		if model then tryAttack(model) end
	elseif SLOT_KEYS[input.KeyCode] and spellBar.Visible then
		S.selected = math.min(SLOT_KEYS[input.KeyCode], math.max(1, #S.slots))
		castSlot(SLOT_KEYS[input.KeyCode])
	elseif (input.KeyCode == Enum.KeyCode.DPadRight or input.KeyCode == Enum.KeyCode.DPadLeft) and #S.slots > 0 and spellBar.Visible then
		local step = if input.KeyCode == Enum.KeyCode.DPadRight then 1 else -1
		S.selected = (S.selected - 1 + step) % #S.slots + 1
	elseif input.KeyCode == Enum.KeyCode.ButtonL1 and spellBar.Visible then
		castSlot(S.selected)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if (input.UserInputType == Enum.UserInputType.MouseButton1 and held == "mouse")
		or (input.KeyCode == Enum.KeyCode.ButtonR2 and held == "pad") then
		held = nil
	end
end)
UserInputService.TouchTapInWorld:Connect(function(position, processed)
	if processed then return end
	local model = pick(position)
	if model then tryAttack(model) end
end)
-- §34: "Attack" from the world context menu (overlay.client.lua) on
-- ReplicatedStorage.IsleAttackLocal:Fire(model). In reach it swings now;
-- otherwise the character walks over (Humanoid:MoveTo) and swings on arrival
-- (checked each frame for at most 6 s; any new attack input replaces it).
do
	local attackLocal = ReplicatedStorage:FindFirstChild("IsleAttackLocal") or make("BindableEvent", ReplicatedStorage, {Name = "IsleAttackLocal"})
	attackLocal.Event:Connect(function(model)
		-- "cancel": the overlay is driving a prompt / walking elsewhere (§34 M2).
		if model == "cancel" then S.pendingAttack = nil return end
		if typeof(model) ~= "Instance" or not canTarget(model) then return end
		setTarget(model)
		S.pendingAttack = nil
		if distanceTo(model) <= reach() then tryAttack(model) return end
		local _, humanoid = rootOf()
		local body = model.PrimaryPart
		if humanoid and body then
			humanoid:MoveTo(body.Position)
			S.pendingAttack = {model = model, untilAt = os.clock() + 6}
		end
	end)
end
if attackButton then
	attackButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			held = "button"
			local model = nearestMonster(true)
			if model then tryAttack(model) end
		end
	end)
	attackButton.InputEnded:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1) and held == "button" then
			held = nil
		end
	end)
end

-- Snapshot facts: Attack Speed for local pacing, and depth.combat (style,
-- weapon, quiver, supplies, levels, autocast) for the verb, reach and spell bar.
local function acceptSnapshot(state)
	local depth = type(state) == "table" and state.depth
	if type(depth) ~= "table" then return end
	local stats = depth.stats
	if type(stats) == "table" and tonumber(stats.attackSpeed) then attackSpeed = tonumber(stats.attackSpeed) end
	local c = depth.combat
	if type(c) ~= "table" then return end
	local l = S.loadout
	l.style = if STYLE_LOOK[c.style] then c.style else "melee"
	l.weapon = if type(c.weapon) == "string" then c.weapon else nil
	l.ammo = if type(c.ammo) == "string" then c.ammo else nil
	l.ammoCount = tonumber(c.ammoCount) or 0
	l.supplies = if type(c.supplies) == "table" then c.supplies else {}
	l.levels = if type(c.levels) == "table" then c.levels else {}
	l.autocast = if type(c.autocast) == "string" then c.autocast else nil
	S.quiver = if l.ammo then l.ammoCount else 0
	paintSlots()
end
task.spawn(function()
	local updates = ReplicatedStorage:WaitForChild("IsleUpdate", 60)
	if updates and updates:IsA("RemoteEvent") then updates.OnClientEvent:Connect(acceptSnapshot) end
end)
-- Snapshots the atlas receives as InvokeServer results never reach IsleUpdate.
task.spawn(function()
	local channel = ReplicatedStorage:WaitForChild("IsleSnapshotLocal", 60)
	if channel and channel:IsA("BindableEvent") and channel.Event then
		channel.Event:Connect(acceptSnapshot)
		-- Ask the atlas for the snapshot it already holds (it may have synced first).
		local ask = ReplicatedStorage:FindFirstChild("IsleActionLocal")
		if ask and ask:IsA("BindableEvent") then ask:Fire("snapshot") end
	end
end)
player:GetAttributeChangedSignal("QuiverCount"):Connect(function()
	local n = tonumber(player:GetAttribute("QuiverCount"))
	if n then
		S.quiver = n
		S.loadout.ammoCount = n
		if S.loadout.ammo then S.loadout.supplies[S.loadout.ammo] = n end
	end
end)

------------------------------------------------------------------------------
-- Floating numbers, hit flash, death burst
------------------------------------------------------------------------------
local function commas(n)
	local s = tostring(math.floor(n))
	while true do
		local replaced, count = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		s = replaced
		if count == 0 then return s end
	end
end
------------------------------------------------------------------------------
-- Hitsplats (§34): pooled billboards on pooled Terrain attachments. Each splat
-- is a top-lit badge (a rounded diamond; crits add an amber starburst) with the
-- number in the pixel face and an optional tag (WEAK! / resist). Styles come
-- from HudDepth.splatStyle: damage red, crit amber + larger, miss blue "miss",
-- heal green, resist grey. At most SP.POOL exist; when all are live the oldest
-- is restyled. Hits on one model within 0.6 s fan out so numbers never stack.
------------------------------------------------------------------------------
local SP = {POOL = 24, LIFE = 0.95, free = {}, live = {}, count = 0, fan = setmetatable({}, {__mode = "k"})}
SP.FAN = {Vector3.new(0, 0, 0), Vector3.new(-1.2, 0.5, 0), Vector3.new(1.2, 0.5, 0), Vector3.new(0, 1.2, 0), Vector3.new(-0.8, -0.6, 0), Vector3.new(0.8, -0.6, 0)}
function SP.new()
	local anchor = make("Attachment", Workspace.Terrain, {Name = "Hitsplat"})
	local board = make("BillboardGui", anchor, {Name = "Splat", Size = UDim2.fromOffset(120, 64), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 140,
		Enabled = false, ResetOnSpawn = false})
	local burst = make("Frame", board, {Name = "Burst", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(40, 40),
		BorderSizePixel = 0, Visible = false})
	make("UICorner", burst, {CornerRadius = UDim.new(0, 4)})
	local badge = make("Frame", board, {Name = "Badge", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(32, 32),
		Rotation = 45, BorderSizePixel = 0, ZIndex = 2})
	make("UICorner", badge, {CornerRadius = UDim.new(0, 7)})
	local edge = make("UIStroke", badge, {Name = "Edge", Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
	-- Lit from the top: the badge is turned 45°, so the gradient turns back.
	make("UIGradient", badge, {Rotation = 45, Color = ColorSequence.new(white, Color3.new(0.58, 0.58, 0.58))})
	local value = make("TextLabel", board, {Name = "Value", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.new(1, 0, 0, 24), Font = display, TextSize = 16, TextColor3 = white, TextStrokeTransparency = 0, TextStrokeColor3 = deep, Text = "", ZIndex = 3,
		RichText = true})
	local tag = make("TextLabel", board, {Name = "Tag", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.68),
		Size = UDim2.new(1, 0, 0, 14), Font = heavy, TextSize = 12, TextColor3 = gold, TextStrokeTransparency = 0.1, TextStrokeColor3 = deep, Text = "", ZIndex = 3})
	return {anchor = anchor, board = board, burst = burst, badge = badge, edge = edge, value = value, tag = tag, token = 0, tweens = {}}
end
-- Stops a pooled object's running tweens (a reused splat or bar must not keep
-- fading from its previous life).
local function stopTweens(o)
	for _, tween in ipairs(o.tweens) do pcall(function() tween:Cancel() end) end
	table.clear(o.tweens)
end
local function play(o, object, info, goals)
	local tween = TweenService:Create(object, info, goals)
	table.insert(o.tweens, tween)
	tween:Play()
	return tween
end
function SP.take()
	local s = table.remove(SP.free)
	if not s then
		if SP.count < SP.POOL then
			SP.count += 1
			s = SP.new()
		else
			s = table.remove(SP.live, 1) -- every splat is live: restyle the oldest
		end
	else
		local i = table.find(SP.live, s)
		if i then table.remove(SP.live, i) end
	end
	table.insert(SP.live, s)
	return s
end
-- style = HudDepth.splatStyle(...) or {kind = "text", text, ink (Color3), size}.
function SP.show(position, style, model)
	local s = SP.take()
	s.token += 1
	stopTweens(s)
	local token = s.token
	local offset = Vector3.zero
	if model then
		local fan = SP.fan[model]
		local now = os.clock()
		if not fan or now - fan.at > 0.6 then fan = {n = 0, at = now}; SP.fan[model] = fan end
		fan.n, fan.at = fan.n % #SP.FAN + 1, now
		offset = SP.FAN[fan.n]
	end
	s.anchor.WorldPosition = position + offset
	s.board.StudsOffsetWorldSpace = Vector3.zero
	local text = style.kind == "text"
	local scale = style.scale or 1
	s.badge.Visible = not text
	s.burst.Visible = style.kind == "crit"
	if not text then
		local fill = rgb(style.fill)
		s.badge.BackgroundColor3 = fill
		local shape, bw, bh = HD.splatShape(style.text, style.size)
		s.badge.Rotation = if shape == "diamond" then 45 else 0
		s.badge.Size = UDim2.fromOffset(math.floor(bw * scale), math.floor(bh * scale))
		s.badge:FindFirstChildOfClass("UIGradient").Rotation = if shape == "diamond" then 45 else 90
		s.edge.Color = rgb(style.edge)
		s.burst.BackgroundColor3 = fill:Lerp(white, 0.35)
		s.burst.Size = UDim2.fromOffset(math.floor(40 * scale), math.floor(40 * scale))
	end
	s.value.Text = style.text
	s.value.Font = if text then heavy else display
	s.value.TextSize = style.size or 16
	s.value.TextColor3 = if typeof(style.ink) == "Color3" then style.ink else rgb(style.ink or "FFFFFF")
	s.tag.Text = style.tag or ""
	s.tag.TextColor3 = if style.tagColor then rgb(style.tagColor) else gold
	s.tag.Visible = style.tag ~= nil
	for _, o in ipairs({s.value, s.tag}) do o.TextTransparency, o.TextStrokeTransparency = 0, 0.05 end
	s.badge.BackgroundTransparency, s.burst.BackgroundTransparency, s.edge.Transparency = 0.04, 0.15, 0
	s.board.Enabled = true
	if not Theme.reducedMotion(player) then
		-- Rise and fade; crits pop from 1.5x.
		play(s, s.board, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {StudsOffsetWorldSpace = Vector3.new(0, 1.8, 0)})
		if style.kind == "crit" then
			s.board.Size = UDim2.fromOffset(180, 96)
			play(s, s.board, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.fromOffset(120, 64)})
		else
			s.board.Size = UDim2.fromOffset(120, 64)
		end
		local fade = TweenInfo.new(0.35, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.55)
		play(s, s.value, fade, {TextTransparency = 1, TextStrokeTransparency = 1})
		play(s, s.tag, fade, {TextTransparency = 1, TextStrokeTransparency = 1})
		play(s, s.badge, fade, {BackgroundTransparency = 1})
		play(s, s.edge, fade, {Transparency = 1})
		play(s, s.burst, fade, {BackgroundTransparency = 1})
	end
	task.delay(SP.LIFE, function()
		if s.token ~= token then return end
		s.board.Enabled = false
		local i = table.find(SP.live, s)
		if i then table.remove(SP.live, i) end
		table.insert(SP.free, s)
	end)
	return s
end
S.splats = SP
floatText = function(position, text, color, size)
	SP.show(position, {kind = "text", text = text, ink = color, size = size})
end

------------------------------------------------------------------------------
-- Overhead health bars (§34): a slim bar over each creature you fight (hit by
-- you, or your current target; other players' hits never claim one), with a pale "recent damage" trail that drains after it. Bars
-- are pooled (OB.POOL), listen to the creature's Health attribute (no per-frame
-- work) and fade out OB.LINGER s after the last hit; a dead or removed creature
-- releases its bar at once.
------------------------------------------------------------------------------
local OB = {POOL = 12, LINGER = 5, free = {}, byModel = {}, count = 0, clock = 0}
function OB.new()
	local board = make("BillboardGui", nil, {Name = "OverheadBar", Size = UDim2.fromOffset(78, 23), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 90,
		Enabled = false, ResetOnSpawn = false})
	local well = make("Frame", board, {Name = "Track", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.new(1, -4, 0, 9),
		BackgroundColor3 = track, BackgroundTransparency = 0.1, BorderSizePixel = 0})
	make("UICorner", well, {CornerRadius = UDim.new(0, 3)})
	make("UIStroke", well, {Name = "Rim", Color = brassDark, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
	local trail = make("Frame", well, {Name = "Trail", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb("FFE6C8"), BorderSizePixel = 0})
	make("UICorner", trail, {CornerRadius = UDim.new(0, 3)})
	local fill = make("Frame", well, {Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = mint, BorderSizePixel = 0, ZIndex = 2})
	make("UICorner", fill, {CornerRadius = UDim.new(0, 3)})
	make("UIGradient", fill, {Rotation = 90, Color = ColorSequence.new(white, Color3.new(0.62, 0.62, 0.62))})
	local level = make("TextLabel", board, {Name = "Level", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -12),
		Size = UDim2.new(1, 0, 0, 11), Font = display, TextSize = 11, TextColor3 = ivory, TextStrokeTransparency = 0.2, TextStrokeColor3 = deep,
		TextXAlignment = Enum.TextXAlignment.Left, Text = ""})
	return {board = board, well = well, trail = trail, fill = fill, level = level, token = 0, tweens = {}, touched = 0}
end
function OB.release(model)
	local b = OB.byModel[model]
	if not b then return end
	OB.byModel[model] = nil
	for _, c in ipairs(b.connections or {}) do c:Disconnect() end
	b.connections = nil
	b.board.Enabled = false
	b.board.Adornee = nil
	b.values = nil
	b.token += 1
	stopTweens(b)
	OB.opacity(b, 0)
	table.insert(OB.free, b)
end
function OB.paint(model, b, animate)
	local hp, maxHp = tonumber(model:GetAttribute("Health")) or 0, math.max(1, tonumber(model:GetAttribute("MaxHealth")) or 1)
	-- §42: a gathering node's bar shows YOUR progress on it (per player, from the strike reply).
	if b.values then hp, maxHp = b.values.hp, math.max(1, b.values.max) end
	local f = math.clamp(hp / maxHp, 0, 1)
	b.fill.Size = UDim2.fromScale(f, 1)
	b.fill.Visible = f > 0
	b.fill.BackgroundColor3 = rgb(HD.barColor(f))
	if animate and not Theme.reducedMotion(player) then
		play(b, b.trail, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.25), {Size = UDim2.fromScale(f, 1)})
	else
		b.trail.Size = UDim2.fromScale(f, 1)
	end
	if (model:GetAttribute("Dead") or hp <= 0) and not b.values then OB.release(model) end
end
-- Shows (or refreshes) the bar over `model`, fading LINGER s after the last call.
function OB.touch(model)
	if typeof(model) ~= "Instance" or not model.Parent then return nil end
	local b = OB.byModel[model]
	if not b then
		b = table.remove(OB.free)
		if not b and OB.count >= OB.POOL then
			-- Pool full: hand back the bar idle longest that is not over your target.
			local oldest, at = nil, math.huge
			for m, other in pairs(OB.byModel) do
				if m ~= target and other.touched < at then oldest, at = m, other.touched end
			end
			if not oldest then return nil end
			OB.release(oldest)
			b = table.remove(OB.free)
		end
		if not b then
			OB.count += 1
			b = OB.new()
		end
		OB.byModel[model] = b
		local body = if model:IsA("BasePart") then model else (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) -- §42: a node host is its own body
		if not body then
			for _, child in ipairs(model:GetChildren()) do if child:IsA("BasePart") then body = child break end end
		end
		b.board.Adornee = body
		b.board.StudsOffsetWorldSpace = Vector3.new(0, (if body then body.Size.Y / 2 else 2) + 1.6, 0)
		b.board.Parent = player:FindFirstChild("PlayerGui")
		local lvl = model:GetAttribute("Level")
		b.level.Text = if lvl then "Lv " .. tostring(lvl) else ""
		b.connections = {
			model:GetAttributeChangedSignal("Health"):Connect(function() OB.paint(model, b, true) end),
			model.AncestryChanged:Connect(function() if not model:IsDescendantOf(Workspace) then OB.release(model) end end),
		}
		b.trail.Size = UDim2.fromScale(1, 1)
		b.values = OB.pendingValues
		OB.paint(model, b, false)
		if OB.byModel[model] ~= b then return nil end
	end
	b.board.Enabled = true
	stopTweens(b)
	OB.opacity(b, 0)
	OB.clock += 1
	b.touched = OB.clock -- touch order (eviction picks the smallest)
	b.token += 1
	local token = b.token
	task.delay(OB.LINGER, function()
		if b.token ~= token or OB.byModel[model] ~= b or model == target then return end
		-- Out of combat: fade, then hand the bar back to the pool.
		if not Theme.reducedMotion(player) then
			local info = TweenInfo.new(0.4)
			for _, o in ipairs({b.well, b.trail, b.fill}) do play(b, o, info, {BackgroundTransparency = 1}) end
			play(b, b.level, info, {TextTransparency = 1, TextStrokeTransparency = 1})
		end
		task.delay(0.45, function() if b.token == token and OB.byModel[model] == b then OB.release(model) end end)
	end)
	return b
end
-- §42: the bar over a gathering node shows the local player's own progress
-- (hp / maxHp from the strike reply; nodes have no shared Health), captioned
-- with the skill and level ("Mining 30") or the fishing state ("Bite!").
function OB.touchNode(node, hp, maxHp, caption)
	local b = OB.byModel[node]
	if b then
		b.values = {hp = hp, max = maxHp}
		OB.paint(node, b, true)
	end
	OB.pendingValues = {hp = hp, max = maxHp}
	b = OB.touch(node)
	OB.pendingValues = nil
	if b and caption then b.level.Text = caption end
	return b
end
-- Resets the fade (0 = fully shown).
function OB.opacity(b, t)
	b.well.BackgroundTransparency = math.max(t, 0.1)
	b.trail.BackgroundTransparency, b.fill.BackgroundTransparency = t, t
	b.level.TextTransparency, b.level.TextStrokeTransparency = t, math.max(t, 0.2)
end
S.overhead = OB
-- One reusable flash Highlight per monster (Roblox renders at most 31 at once);
-- it is disabled between hits and destroyed when the monster leaves the world.
local flashes = {} -- [model] = {highlight = Highlight, token = number}
local function dropFlash(model)
	local entry = flashes[model]
	if not entry then return end
	flashes[model] = nil
	if entry.connection then entry.connection:Disconnect() end
	entry.highlight:Destroy()
end
local function flash(model)
	if not model or not model.Parent then return end
	local entry = flashes[model]
	if not entry then
		entry = {token = 0, highlight = make("Highlight", Workspace.CurrentCamera, {
			Adornee = model, FillColor = Color3.new(1, 1, 1), FillTransparency = 1, OutlineTransparency = 1,
			DepthMode = Enum.HighlightDepthMode.Occluded, Enabled = false,
		})}
		flashes[model] = entry
		entry.connection = model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(Workspace) then dropFlash(model) end
		end)
	end
	entry.token += 1
	local token = entry.token
	local highlight = entry.highlight
	highlight.Enabled = true
	highlight.FillTransparency = 0.35
	TweenService:Create(highlight, TweenInfo.new(0.18), {FillTransparency = 1}):Play()
	task.delay(0.2, function()
		if flashes[model] ~= entry or entry.token ~= token then return end
		highlight.Enabled = false
		if not model.Parent then dropFlash(model) end
	end)
end
local function burst(position, color, scale)
	local tint = rgb(color)
	for i = 1, 12 do
		local size = (0.35 + math.random() * 0.4) * (scale or 1)
		local bit = make("Part", Workspace.CurrentCamera, {
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
			Material = Enum.Material.Neon, Color = if i % 3 == 0 then gold else tint, Size = Vector3.new(size, size, size),
			CFrame = CFrame.new(position),
		})
		local direction = Vector3.new(math.random() - 0.5, math.random() * 0.8 + 0.2, math.random() - 0.5).Unit
		TweenService:Create(bit, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(position + direction * (4 + math.random() * 3) * (scale or 1)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
			Transparency = 1, Size = Vector3.new(0.05, 0.05, 0.05),
		}):Play()
		task.delay(0.6, function() bit:Destroy() end)
	end
end

------------------------------------------------------------------------------
-- Style FX: projectiles (arrow trails, element bolts), snare vines, heal burst,
-- teleport flash. Built from Neon parts, Trails and the built-in sparkle texture.
------------------------------------------------------------------------------
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local function fxPart(props)
	local part = make("Part", nil, {Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Material = Enum.Material.Neon})
	for k, v in pairs(props) do part[k] = v end
	return part
end
local function trail(part, color, a, b, lifetime, width)
	local a0 = make("Attachment", part, {Position = a})
	local a1 = make("Attachment", part, {Position = b})
	make("Trail", part, {Attachment0 = a0, Attachment1 = a1, Color = ColorSequence.new(color), LightEmission = 1, FaceCamera = true,
		Lifetime = lifetime, Transparency = NumberSequence.new(0.15, 1), WidthScale = NumberSequence.new(width or 1, 0)})
end
local function sparkles(part, color, rate)
	if not NumberRange then return end
	make("ParticleEmitter", part, {Texture = SPARKLE, Color = ColorSequence.new(color), Rate = rate, LightEmission = 1,
		Lifetime = NumberRange.new(0.2, 0.4), Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.45, 0), Transparency = NumberSequence.new(0, 1)})
end
local function spellColor(payload)
	local spell = spellDef(payload.spell)
	return rgb(payload.color or (spell and spell.color) or "C9F2FF")
end
local function projectile(payload)
	local from, to = payload.from, payload.to
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then return end
	local distance = (to - from).Magnitude
	if distance < 0.5 then return end
	local camera = Workspace.CurrentCamera
	local ranged = payload.style == "ranged"
	local color = if ranged then rgb(payload.color or "C49A6C") else spellColor(payload)
	local duration = math.clamp(distance / (if ranged then 140 else 90), 0.08, 0.6)
	local part
	if ranged then
		-- Arrow: a wooden shaft with a tier-coloured head and a pale vane trail.
		part = fxPart({Material = Enum.Material.Wood, Color = rgb("C49A6C"), Size = Vector3.new(0.12, 0.12, 2)})
		local head = fxPart({Material = Enum.Material.Metal, Color = color, Size = Vector3.new(0.2, 0.2, 0.35)})
		head.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -1.1)
		local weld = make("WeldConstraint", head, {Part0 = part, Part1 = head})
		head.Anchored = false
		head.Parent = part
		trail(part, rgb("F4F1E6"), Vector3.new(0, 0.12, 0.9), Vector3.new(0, -0.12, 0.9), 0.15, 1)
		weld.Enabled = true
	else
		-- Bolt: a glowing element orb with a trail, light and sparkles.
		part = fxPart({Color = color, Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8), Transparency = 0.1})
		trail(part, color, Vector3.new(0, 0.35, 0), Vector3.new(0, -0.35, 0), 0.22, 1.4)
		make("PointLight", part, {Color = color, Brightness = 2, Range = 8})
		sparkles(part, color, 40)
	end
	part.CFrame = CFrame.lookAt(from, to)
	part.Parent = camera
	TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = CFrame.lookAt(to, to + (to - from).Unit)}):Play()
	task.delay(duration, function()
		if not ranged then burst(to, payload.color or "C9F2FF", 0.45) end
		part.Transparency = 1
		task.delay(0.3, function() part:Destroy() end)
	end)
end
-- Rootbind: a ring of vines at the creature's feet for the snare's duration.
local function snare(payload)
	local model = payload.model
	local duration = math.clamp(tonumber(payload.duration) or 4, 0.5, 15)
	local feet
	if typeof(model) == "Instance" and model.Parent and model:IsA("Model") then
		local cf, size = model:GetBoundingBox()
		feet = cf.Position - Vector3.new(0, size.Y / 2, 0)
	elseif typeof(payload.position) == "Vector3" then
		feet = payload.position - Vector3.new(0, 3, 0)
	else
		return
	end
	local green = rgb("5E8C4A")
	local holder = make("Model", nil, {Name = "Rootbind"})
	local ring = fxPart({Shape = Enum.PartType.Cylinder, Color = rgb("7BC96F"), Size = Vector3.new(0.25, 7, 7), Transparency = 0.45,
		CFrame = CFrame.new(feet + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))})
	ring.Parent = holder
	for i = 1, 6 do
		local angle = i / 6 * math.pi * 2
		local vine = fxPart({Material = Enum.Material.Grass, Color = green, Size = Vector3.new(0.35, 2.6, 0.35),
			CFrame = CFrame.new(feet + Vector3.new(math.cos(angle) * 2.6, 1.1, math.sin(angle) * 2.6)) * CFrame.Angles(math.sin(angle) * 0.5, 0, -math.cos(angle) * 0.5)})
		vine.Parent = holder
	end
	sparkles(ring, rgb("9BE38B"), 18)
	holder.Parent = Workspace.CurrentCamera
	TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Transparency = 0.75}):Play()
	task.delay(duration, function() holder:Destroy() end)
end
-- Mend: green motes rising around the caster.
local function healBurst()
	local root = rootOf()
	if not root then return end
	for i = 1, 10 do
		local angle = i / 10 * math.pi * 2
		local start = root.Position + Vector3.new(math.cos(angle) * 1.8, -2, math.sin(angle) * 1.8)
		local mote = fxPart({Shape = Enum.PartType.Ball, Color = if i % 3 == 0 then gold else rgb("6BBF59"), Size = Vector3.new(0.35, 0.35, 0.35), CFrame = CFrame.new(start)})
		mote.Parent = Workspace.CurrentCamera
		TweenService:Create(mote, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(start + Vector3.new(0, 4 + math.random() * 1.5, 0)), Transparency = 1}):Play()
		task.delay(0.85, function() mote:Destroy() end)
	end
	floatText(root.Position + Vector3.new(0, 3, 0), "✚ Mend", rgb("8EE07F"), 18)
end
-- Hubward: a gold flash where the caster arrives.
local function teleportFlash()
	local root = rootOf()
	if not root then return end
	local flashBall = fxPart({Shape = Enum.PartType.Ball, Color = rgb("F9CC77"), Size = Vector3.new(1, 1, 1), Transparency = 0.2, CFrame = CFrame.new(root.Position)})
	make("PointLight", flashBall, {Color = rgb("F9CC77"), Brightness = 4, Range = 16})
	flashBall.Parent = Workspace.CurrentCamera
	TweenService:Create(flashBall, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = Vector3.new(11, 11, 11), Transparency = 1}):Play()
	task.delay(0.5, function() flashBall:Destroy() end)
end

fx.OnClientEvent:Connect(function(kind, payload)
	if type(payload) ~= "table" then return end
	if kind == "hit" and typeof(payload.position) == "Vector3" then
		-- §34 hitsplats: miss (blue), damage (red), crit (amber burst), with the
		-- triangle tags WEAK! (gold) and resist (grey); a creature you hit (or your
		-- current target) gets an overhead bar; other players' hits do not.
		local model = if typeof(payload.model) == "Instance" then payload.model else nil
		SP.show(payload.position, HD.splatStyle(payload, Theme), model)
		if model then
			if payload.attacker == player.UserId or model == target then OB.touch(model) end
			if not payload.miss then flash(model) end
		end
	elseif kind == "projectile" then
		projectile(payload)
	elseif kind == "snare" then
		snare(payload)
	elseif kind == "heal" then
		healBurst()
	elseif kind == "teleport" then
		teleportFlash()
	elseif kind == "denied" then
		-- Nothing was fired: give the swing (and a just-sent spell's cooldown) back.
		local last = S.lastCast
		if payload.action == "cast" and last and os.clock() - last.at < 1 then
			S.readyAt[last.id] = nil
			S.lastCast = nil
		end
		S.nextSwing = 0
		toast(deniedText(payload.action, payload.reason))
	elseif kind == "hurt" then
		local root = rootOf()
		if root then SP.show(root.Position + Vector3.new(0, 2.5, 0), HD.splatStyle({hurt = true, amount = payload.amount}, Theme), player) end
	elseif kind == "death" and typeof(payload.position) == "Vector3" then
		burst(payload.position, payload.color, if payload.boss then 2.2 else 1)
	elseif kind == "bossSpawn" and payload.owner == player.UserId then
		showBanner(tostring(payload.name) .. " has emerged!", rgb("FF7B6E"))
	elseif kind == "bossFail" then
		showBanner(if payload.reason == "timeout" then "The slayer boss slipped away. Time ran out." else "You fell. The slayer boss withdraws.", rgb("FF7B6E"))
	end
end)

------------------------------------------------------------------------------
-- World Boss HUD (Endgame team). IsleCombatFx kinds (combat.server.lua World
-- Boss section):
--   worldBoss          2 Hz, the nearest boss in HUD range only: {id, name, level,
--                      hp, maxHp, phase, phases, phaseName, enraged, enrageIn,
--                      departIn, warded, top = {{name, damage, share, you}},
--                      you = {rank, damage, share, tier}, fighters}
--   telegraph          a warning disc {center, radius, kind disc|ring|safe, windup, name}
--   bossStrike         the impact of a warning
--   worldBossAnnounce  {kind warn|spawn|phase|enrage|win|depart, name, ...}
--   worldBossLoot      {name, eligible, reason, rank, share, tier, drops, coins}
--   (win/depart announcements hide the HUD only for the boss it shows)
-- Layout: the boss bar takes the target panel's top-lane slot (y 10-72, the
-- target panel hides while it shows); the top-5 board sits under the minimap
-- on screens at least 520 px tall, otherwise the bar's last line carries the
-- leader and your rank. The loot summary is a centred card (auto-hides).
------------------------------------------------------------------------------
local WBH = {payload = nil, seenAt = 0, renderedAt = 0, visible = false, discs = {}, lootToken = 0}
WBH.RENDER_INTERVAL = 1 -- the bar re-renders on each payload and on this timer (enrage countdown)
WBH.TIER_COLOR = {Champion = rgb("FFAA00"), Vanguard = rgb("D36BFF"), Valiant = rgb("7C8CFF"), Participant = rgb("7FE3CC")}
WBH.REASON = {share = "You dealt under 1% of its health.", dead = "You fell before it did.", range = "You were too far from the arena.",
	idle = "You had not struck it in the last minute.", ironman = "Ironman journals need 30% of the damage.", sync = "Your journal was syncing; no reward.",
	region = "Your journal may not enter the Shattered Crown yet.", paid = "This fight's reward was already delivered."}
WBH.BAR_HEIGHT = 62
WBH.bar = make("Frame", gui, {Name = "WorldBossBar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.fromOffset(380, WBH.BAR_HEIGHT), BackgroundColor3 = deep, BackgroundTransparency = 0.04, Visible = false})
round(WBH.bar, 12, ember)
sheen(WBH.bar, 0.7)
WBH.title = make("TextLabel", WBH.bar, {Name = "Title", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -96, 0, 18),
	Font = heavy, TextSize = 15, TextColor3 = rgb("FFD86B"), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = ""})
WBH.timer = make("TextLabel", WBH.bar, {Name = "Enrage", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 4), Size = UDim2.fromOffset(78, 18),
	BackgroundColor3 = track, BackgroundTransparency = 0.2, Font = heavy, TextSize = 12, TextColor3 = gold, Text = ""})
round(WBH.timer, 9, brass)
WBH.track = make("Frame", WBH.bar, {Name = "Track", Position = UDim2.fromOffset(12, 24), Size = UDim2.new(1, -24, 0, 16), BackgroundColor3 = track, BorderSizePixel = 0})
round(WBH.track, 8)
WBH.fill = make("Frame", WBH.track, {Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb("DC3C3C"), BorderSizePixel = 0})
round(WBH.fill, 8)
WBH.phaseTicks = {}
for i = 1, 2 do
	WBH.phaseTicks[i] = make("Frame", WBH.track, {Name = "PhaseTick" .. i, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(if i == 1 then 0.66 else 0.33, 0),
		Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = ivory, BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 2})
end
WBH.hpText = make("TextLabel", WBH.track, {Name = "Health", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = heavy, TextSize = 12,
	TextColor3 = ivory, TextStrokeTransparency = 0.3, TextStrokeColor3 = deep, Text = "", ZIndex = 3})
WBH.rankLine = make("TextLabel", WBH.bar, {Name = "Rank", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 42), Size = UDim2.new(1, -24, 0, 16),
	Font = heavy, TextSize = 12, TextColor3 = ivory, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, RichText = true, Text = ""})
-- Damage board (top 5 + you).
WBH.board = make("Frame", gui, {Name = "WorldBossBoard", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 206), Size = UDim2.fromOffset(176, 126),
	BackgroundColor3 = deep, BackgroundTransparency = 0.08, Visible = false})
round(WBH.board, 10, brass)
make("TextLabel", WBH.board, {Name = "Header", BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 16), Font = heavy, TextSize = 12,
	TextColor3 = gold, TextXAlignment = Enum.TextXAlignment.Left, Text = "DAMAGE  ·  TOP 5"})
WBH.rows = {}
for i = 1, 6 do
	WBH.rows[i] = make("TextLabel", WBH.board, {Name = "Row" .. i, BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 4 + i * 17), Size = UDim2.new(1, -20, 0, 16),
		Font = heavy, TextSize = 12, TextColor3 = ivory, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, RichText = true, Text = ""})
end
-- End-of-fight loot summary.
WBH.loot = make("Frame", gui, {Name = "WorldBossLoot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(340, 210),
	BackgroundColor3 = deep, BackgroundTransparency = 0.02, Visible = false, ZIndex = 10})
round(WBH.loot, 14, gold)
sheen(WBH.loot, 0.6)
make("UISizeConstraint", WBH.loot, {MaxSize = Vector2.new(340, 210)})
WBH.lootTitle = make("TextLabel", WBH.loot, {Name = "Title", BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -52, 0, 22),
	Font = display, TextSize = 18, TextColor3 = gold, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = "", ZIndex = 11})
WBH.lootClose = make("TextButton", WBH.loot, {Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(28, 28),
	BackgroundColor3 = raised, Font = heavy, TextSize = 14, TextColor3 = ivory, Text = "✕", ZIndex = 11})
round(WBH.lootClose, 14, brass)
WBH.lootClose.Activated:Connect(function() WBH.loot.Visible = false end)
WBH.lootStanding = make("TextLabel", WBH.loot, {Name = "Standing", BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -28, 0, 18),
	Font = heavy, TextSize = 14, TextColor3 = ivory, TextXAlignment = Enum.TextXAlignment.Left, RichText = true, Text = "", ZIndex = 11})
WBH.lootList = make("TextLabel", WBH.loot, {Name = "Items", BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 58), Size = UDim2.new(1, -28, 1, -66),
	Font = heavy, TextSize = 13, TextColor3 = ivory, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
	RichText = true, Text = "", ZIndex = 11})

function WBH.itemName(id)
	local def = Data and type(Data.Items) == "table" and Data.Items[id]
	return if type(def) == "table" and type(def.name) == "string" then def.name else tostring(id)
end
function WBH.itemColor(id)
	local def = Data and type(Data.Items) == "table" and Data.Items[id]
	local rarity = type(def) == "table" and Data.Rarity and Data.Rarity[def.rarity]
	return if rarity and type(rarity.color) == "string" then rarity.color else "F7EFDC"
end
function WBH.percent(share) return string.format("%.1f%%", (tonumber(share) or 0) * 100) end
function WBH.clock(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end
-- Places the bar in the top lane (or at the top of the left column on narrow
-- screens) and the board under the minimap when the screen is tall enough.
-- §39 QC M3: the board's foot (px from the top; 0 = hidden) as the local
-- attribute WorldBossBoard, so the atlas's contest tracker stacks below it.
function WBH.publish()
	local foot = if WBH.board.Visible then WBH.board.Position.Y.Offset + WBH.board.Size.Y.Offset else 0
	if player:GetAttribute("WorldBossBoard") ~= foot then player:SetAttribute("WorldBossBoard", foot) end
end
function WBH.layout()
	local view = gui.AbsoluteSize
	local width = if view and view.X > 0 then view.X else 1280
	local height = if view and view.Y > 0 then view.Y else 720
	if not placeInLane(WBH.bar, 380, EDGE, WBH.BAR_HEIGHT, width) then
		local _, right = laneFor(width)
		WBH.bar.AnchorPoint, WBH.bar.Position = Vector2.new(0, 0), UDim2.fromOffset(EDGE, BELOW_HUD)
		WBH.bar.Size = UDim2.fromOffset(math.max(160, math.min(380, right - EDGE)), WBH.BAR_HEIGHT)
	end
	local L = lanes()
	WBH.tall = height >= 520
	WBH.board.AnchorPoint = Vector2.new(1, 0)
	WBH.board.Position = UDim2.fromOffset(L.rightEdge, L.rightTop)
	WBH.board.Size = UDim2.fromOffset(math.min(L.sidebar.w, 214), 126)
	WBH.publish()
end
function WBH.render()
	local p = WBH.payload
	if not p then return end
	WBH.renderedAt = os.clock()
	local hp, maxHp = tonumber(p.hp) or 0, math.max(1, tonumber(p.maxHp) or 1)
	local fraction = math.clamp(hp / maxHp, 0, 1)
	WBH.title.Text = "☠ " .. tostring(p.name or "World boss") .. "  ·  Phase " .. tostring(p.phase or 1) .. "/" .. tostring(p.phases or 3)
		.. (if type(p.phaseName) == "string" then " " .. p.phaseName else "")
	WBH.fill.Size = UDim2.fromScale(fraction, 1)
	WBH.fill.Visible = fraction > 0
	WBH.fill.BackgroundColor3 = if p.warded then rgb("8E7CF0") elseif p.enraged then rgb("FF4F3A") else rgb("DC3C3C")
	WBH.hpText.Text = commas(hp) .. " / " .. commas(maxHp) .. (if p.warded then "  ·  WARDED" else "")
	local elapsed = os.clock() - WBH.seenAt
	if p.enraged then
		WBH.timer.Text, WBH.timer.TextColor3 = "ENRAGED", rgb("FF7B6E")
	else
		WBH.timer.Text, WBH.timer.TextColor3 = "Enrage " .. WBH.clock((tonumber(p.enrageIn) or 0) - elapsed), gold
	end
	local you = type(p.you) == "table" and p.you or nil
	local top = type(p.top) == "table" and p.top or {}
	local line
	if you then
		local tier = tostring(you.tier or "below credit")
		local color = WBH.TIER_COLOR[you.tier]
		local hex = if color then string.format("%02X%02X%02X", math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255)) else "A9BDC1"
		line = "You <b>#" .. tostring(you.rank) .. "</b>  ·  " .. WBH.percent(you.share) .. '  ·  <font color="#' .. hex .. '">' .. tier .. "</font>"
	else
		line = '<font color="#A9BDC1">Strike it to join the damage board</font>'
	end
	if not WBH.tall and top[1] and not (top[1].you) then
		line ..= "  ·  #1 " .. tostring(top[1].name) .. " " .. WBH.percent(top[1].share)
	end
	WBH.rankLine.Text = line
	WBH.board.Visible = WBH.tall == true and #top > 0
	WBH.publish()
	for i, row in ipairs(WBH.rows) do
		local e = top[i]
		if i == 6 and you and you.rank and you.rank > 5 then
			row.Text = '<font color="#7FE3CC">' .. tostring(you.rank) .. ". You  " .. WBH.percent(you.share) .. "</font>"
		elseif e then
			local name = tostring(e.name)
			row.Text = (if e.you then '<font color="#7FE3CC">' else "") .. i .. ". " .. name .. "  " .. WBH.percent(e.share) .. (if e.you then "</font>" else "")
		else
			row.Text = ""
		end
	end
end
function WBH.show(payload)
	WBH.payload, WBH.seenAt = payload, os.clock()
	if not WBH.visible then
		WBH.visible = true
		layoutKey = nil
		WBH.layout()
	end
	WBH.bar.Visible = true
	WBH.render()
end
function WBH.hide()
	WBH.visible = false
	WBH.payload = nil
	WBH.bar.Visible = false
	WBH.board.Visible = false
	WBH.publish()
end
-- Warning discs: a translucent cylinder that fills over the windup; "safe"
-- marks the shelter (green) inside a red arena ring.
function WBH.disc(payload)
	local center = payload.center
	if typeof(center) ~= "Vector3" then return end
	local radius = math.clamp(tonumber(payload.radius) or 8, 2, 60)
	local windup = math.clamp(tonumber(payload.windup) or 2, 0.3, 6)
	local safe = payload.kind == "safe"
	local disc = fxPart({Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = if safe then rgb("6BE38B") else rgb("FF4F3A"),
		Transparency = 0.55, Size = Vector3.new(0.2, radius * 2, radius * 2), CFrame = CFrame.new(center + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.pi / 2)})
	disc.Name = "BossTelegraph"
	disc.Parent = Workspace.CurrentCamera
	TweenService:Create(disc, TweenInfo.new(windup, Enum.EasingStyle.Linear), {Transparency = 0.25}):Play()
	table.insert(WBH.discs, disc)
	task.delay(windup + 0.15, function()
		local i = table.find(WBH.discs, disc)
		if i then table.remove(WBH.discs, i) end
		disc:Destroy()
	end)
	if payload.name then toast(tostring(payload.name) .. (if safe then "! Get close to the boss!" elseif payload.kind == "ring" then "! Get clear of the boss!" else "! Leave the red circle!")) end
end
function WBH.lootCard(p)
	WBH.lootToken += 1
	local token = WBH.lootToken
	WBH.lootTitle.Text = tostring(p.name or "World boss") .. (if p.eligible then " defeated" else " · no reward")
	if p.eligible then
		local color = WBH.TIER_COLOR[p.tier] or ivory
		local hex = string.format("%02X%02X%02X", math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
		WBH.lootStanding.Text = "#" .. tostring(p.rank) .. "  ·  " .. WBH.percent(p.share) .. ' of its health  ·  <font color="#' .. hex .. '">' .. tostring(p.tier) .. "</font>"
		local lines = {}
		if tonumber(p.coins) then table.insert(lines, '<font color="#F3C66E">+' .. commas(tonumber(p.coins)) .. " coins</font>") end
		local ids = {}
		for id in pairs(type(p.drops) == "table" and p.drops or {}) do table.insert(ids, id) end
		table.sort(ids)
		for _, id in ipairs(ids) do
			table.insert(lines, '<font color="#' .. WBH.itemColor(id) .. '">' .. tostring(p.drops[id]) .. "× " .. WBH.itemName(id) .. "</font>")
		end
		WBH.lootList.Text = table.concat(lines, "\n")
	else
		WBH.lootStanding.Text = if p.rank then "#" .. tostring(p.rank) .. "  ·  " .. WBH.percent(p.share) else ""
		WBH.lootList.Text = WBH.REASON[p.reason] or "You did not earn a share of the hoard."
	end
	WBH.loot.Visible = true
	task.delay(15, function() if WBH.lootToken == token then WBH.loot.Visible = false end end)
end
function WBH.announce(p)
	local name = tostring(p.name or "A world boss")
	if p.kind == "warn" then
		showBanner(name .. " rides at dusk. The Eclipse Roost awaits!", rgb("B48CFF"))
	elseif p.kind == "spawn" then
		showBanner(name .. " has awakened in the Shattered Crown!", rgb("FFD86B"))
	elseif p.kind == "phase" then
		showBanner(name .. ": " .. tostring(p.phaseName or ("phase " .. tostring(p.phase))) .. "!", rgb("FF9C8E"))
	elseif p.kind == "enrage" then
		showBanner(name .. " is ENRAGED!", rgb("FF4F3A"))
	elseif p.kind == "win" then
		showBanner(name .. " has fallen!", rgb("FFD86B"))
	elseif p.kind == "depart" then
		showBanner(name .. (if p.reason == "empty" then " withdraws: no challengers remain." else " departs. Time ran out."), rgb("A9BDC1"))
	end
end
fx.OnClientEvent:Connect(function(kind, payload)
	if type(payload) ~= "table" then return end
	if kind == "worldBoss" then
		WBH.show(payload)
	elseif kind == "telegraph" then
		WBH.disc(payload)
	elseif kind == "bossStrike" and typeof(payload.center) == "Vector3" then
		burst(payload.center, if payload.kind == "safe" then "B48CFF" else "FF7B6E", 2)
	elseif kind == "worldBossAnnounce" then
		WBH.announce(payload)
		-- Only the boss this HUD shows (the server sends the nearest one) clears it.
		if (payload.kind == "win" or payload.kind == "depart") and WBH.payload and payload.id == WBH.payload.id then WBH.hide() end
	elseif kind == "worldBossLoot" then
		WBH.lootCard(payload)
	end
end)
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if WBH.visible then WBH.layout() end end)
-- The damage board lives in the right column: step left of (or back from) a docked satchel.
player:GetAttributeChangedSignal("IsleSatchelOpen"):Connect(function() if WBH.visible then WBH.layout() end end)
RunService.RenderStepped:Connect(function()
	if not WBH.visible then return end
	local now = os.clock()
	-- No update for 3 s: out of range or the fight ended unseen.
	if now - WBH.seenAt > 3 then WBH.hide() return end
	-- Payloads render on arrival; between them only the 1 Hz countdown tick.
	if now - WBH.renderedAt >= WBH.RENDER_INTERVAL then WBH.render() end
end)
-- End World Boss HUD.

------------------------------------------------------------------------------
-- Prayer quick bar (Prayer & Thieving team). Above the spell bar, right-
-- aligned with it: a prayer point gauge, the three protection prayers and the
-- two favourites. Driven by player attributes the server publishes:
-- PrayerLevel, PrayerPoints, PrayerMax, PrayerActive / PrayerQuick ("Id,Id").
-- A tap fires IsleActionLocal("prayer", id); the atlas sends the verb and the
-- server decides. Hidden while building or talking (like the spell bar) and
-- until the server publishes PrayerMax. Its height joins IsleHudLift.
------------------------------------------------------------------------------
do
	local PR = Data and type(Data.Prayer) == "table" and Data.Prayer or nil
	local P = {buttons = {}, ids = {}}
	S.prayer = P
	local bar = make("Frame", gui, {Name = "PrayerBar", AnchorPoint = Vector2.new(1, 1), BackgroundTransparency = 1, Size = UDim2.fromOffset(200, 30), Visible = false})
	local gauge = make("Frame", bar, {Name = "Points", BackgroundColor3 = deep, BackgroundTransparency = 0.06, BorderSizePixel = 0, ClipsDescendants = true})
	round(gauge, 9, brass)
	local fill = make("Frame", gauge, {Name = "Fill", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = rgb("E8D9A0"), BackgroundTransparency = 0.55, BorderSizePixel = 0})
	make("UICorner", fill, {CornerRadius = UDim.new(0, 9)})
	local count = make("TextLabel", gauge, {Name = "Count", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = heavy, TextSize = 13,
		TextColor3 = ivory, Text = "", TextStrokeTransparency = 0.4, TextStrokeColor3 = deep, ZIndex = 2})
	for i = 1, 5 do
		local b = make("TextButton", bar, {Name = "Prayer" .. i, Text = "", AutoButtonColor = true, BackgroundColor3 = raised, BackgroundTransparency = 0.04,
			BorderSizePixel = 0, Selectable = true})
		local rim = round(b, 9, brass)
		if rim then rim.Name = "Rim" end
		make("TextLabel", b, {Name = "Glyph", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = heavy, TextSize = 16, TextColor3 = white,
			Text = "", TextStrokeTransparency = 0.35, TextStrokeColor3 = deep, ZIndex = 2})
		make("Frame", b, {Name = "Veil", Size = UDim2.fromScale(1, 1), BackgroundColor3 = track, BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 3, Visible = false})
		local on = make("Frame", b, {Name = "On", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.fromOffset(12, 3),
			BackgroundColor3 = mint, BorderSizePixel = 0, ZIndex = 4, Visible = false})
		make("UICorner", on, {CornerRadius = UDim.new(1, 0)})
		P.buttons[i] = b
		b.Activated:Connect(function()
			local id = P.ids[i]
			local channel = ReplicatedStorage:FindFirstChild("IsleActionLocal")
			if id and channel and channel:IsA("BindableEvent") then channel:Fire("prayer", id) end
		end)
	end
	local function split(value)
		local out = {}
		if type(value) == "string" then for id in value:gmatch("[^,]+") do table.insert(out, id) end end
		return out
	end
	function P.ready() return PR ~= nil and (tonumber(player:GetAttribute("PrayerMax")) or 0) > 0 end
	function P.paint()
		if not PR then return end
		local quick = split(player:GetAttribute("PrayerQuick"))
		P.ids = {PR.ProtectFor.melee, PR.ProtectFor.ranged, PR.ProtectFor.magic, quick[1], quick[2]}
		local active = {}
		for _, id in ipairs(split(player:GetAttribute("PrayerActive"))) do active[id] = true end
		local level = tonumber(player:GetAttribute("PrayerLevel")) or 1
		local points, max = tonumber(player:GetAttribute("PrayerPoints")) or 0, math.max(1, tonumber(player:GetAttribute("PrayerMax")) or 1)
		count.Text = tostring(math.floor(points))
		count.TextColor3 = if points > 0 then ivory else ember
		fill.Size = UDim2.fromScale(1, math.clamp(points / max, 0, 1))
		for i, b in ipairs(P.buttons) do
			local def = P.ids[i] and PR.PrayerById[P.ids[i]]
			local glyph = b:FindFirstChild("Glyph")
			glyph.Text = if def then def.glyph else ""
			glyph.TextColor3 = if def then rgb(def.color) else white
			local open = def ~= nil and level >= def.level
			b:FindFirstChild("Veil").Visible = not open
			glyph.TextTransparency = if open then 0 else 0.55
			local lit = def ~= nil and active[def.id] == true
			b:FindFirstChild("On").Visible = lit
			b.BackgroundColor3 = if lit then rgb("24564F") else raised
			local rim = b:FindFirstChild("Rim")
			if rim then rim.Color = if lit then mint else brass end
		end
	end
	-- Called by layoutSpellBar with the spell slot size; returns the extra lift.
	function S.prayerLayout(size, shown)
		local slot = if size < 48 then 30 else 34
		local gap = 4
		local gaugeWidth = slot + 12
		local width = gaugeWidth + #P.buttons * (slot + gap)
		bar.Size = UDim2.fromOffset(width, slot)
		bar.AnchorPoint = spellBar.AnchorPoint
		bar.Position = if S.spellCentred then UDim2.new(0.5, 0, 1, -S.spellLift0 - size - 6) else UDim2.new(1, -S.spellRight, 1, -S.spellLift0 - size - 6)
		gauge.Size = UDim2.fromOffset(gaugeWidth, slot)
		count.TextSize = if slot < 34 then 12 else 13
		for i, b in ipairs(P.buttons) do
			b.Position = UDim2.fromOffset(gaugeWidth + gap + (i - 1) * (slot + gap), 0)
			b.Size = UDim2.fromOffset(slot, slot)
			b:FindFirstChild("Glyph").TextSize = if slot < 34 then 15 else 17
		end
		local visible = shown and P.ready()
		bar.Visible = visible
		return if visible then slot + 6 else 0
	end
	for _, name in ipairs({"PrayerPoints", "PrayerMax", "PrayerActive", "PrayerQuick", "PrayerLevel"}) do
		player:GetAttributeChangedSignal(name):Connect(function()
			P.paint()
			if bar.Visible ~= (spellBar.Visible and P.ready()) then layoutSpellBar() end
		end)
	end
	P.paint()
	layoutSpellBar()
end
-- End Prayer quick bar.

------------------------------------------------------------------------------
-- Per-frame: held attacks, target panel
------------------------------------------------------------------------------
local function ownBoss()
	for _, model in ipairs(CollectionService:GetTagged("IsleMonster")) do
		if model:GetAttribute("OwnerUserId") == player.UserId and liveMonster(model) then return model end
	end
	return nil
end
local lastBossScan, boss = 0, nil
RunService.RenderStepped:Connect(function()
	if target and (not liveMonster(target) or distanceTo(target) > TARGET_DROP_RANGE) then setTarget(nil) end
	if held then
		S.pendingAttack = nil
		local model = if held == "mouse" then target else nearestMonster()
		if model then tryAttack(model) end
	end
	local pending = S.pendingAttack
	if pending then
		if os.clock() > pending.untilAt or not canTarget(pending.model) then S.pendingAttack = nil
		elseif distanceTo(pending.model) <= reach() then
			S.pendingAttack = nil
			tryAttack(pending.model)
		end
	end
	local now = os.clock()
	if now - lastBossScan > 0.5 then
		lastBossScan = now
		boss = ownBoss()
	end
	-- Talking to townsfolk hides the bar (their dialogue owns the bottom).
	if spellBar.Visible ~= (player:GetAttribute("IslandBuilding") ~= true and not talking()) then layoutSpellBar() end
	if spellBar.Visible then refreshSlots(now) end
	local shown = if boss and liveMonster(boss) then boss else target
	-- World Boss HUD owns the top-lane slot while it shows.
	if WBH.visible then shown = nil end
	if not shown then
		panel.Visible = false
		return
	end
	panel.Visible = true
	local isBoss = shown:GetAttribute("Boss") == true
	local hp, maxHp = shown:GetAttribute("Health") or 0, math.max(1, shown:GetAttribute("MaxHealth") or 1)
	local fraction = math.clamp(hp / maxHp, 0, 1)
	medalText.Text = tostring(shown:GetAttribute("Level") or "?")
	panelName.Text = (if isBoss then "☠ " else "") .. tostring(shown:GetAttribute("DisplayName") or shown.Name)
	panelName.TextColor3 = if isBoss then rgb("FF9C8E") else ivory
	if panelRim then panelRim.Color = if isBoss then ember else brass end
	if medalRim then medalRim.Color = if isBoss then ember else gold end
	medal.BackgroundColor3 = if isBoss then rgb("5A1E1A") else raised
	ornaments.Visible = isBoss
	barFill.Size = UDim2.fromScale(fraction, 1)
	barFill.Visible = fraction > 0
	barCap.Visible = fraction > 0.04 and fraction < 0.995
	barFill.BackgroundColor3 = if isBoss then rgb("DC3C3C") elseif fraction > 0.5 then mint elseif fraction > 0.25 then gold else rgb("E6504A")
	barText.Text = commas(hp) .. " / " .. commas(maxHp)
	layoutHud(isBoss)
	local expires = shown:GetAttribute("ExpiresAt")
	if isBoss and expires then
		local left = math.max(0, math.floor(expires - Workspace:GetServerTimeNow()))
		panelTimer.Text = string.format("%d:%02d", left // 60, left % 60)
		panelTimer.Visible = true
	else
		panelTimer.Text = ""
		panelTimer.Visible = false
	end
end)

------------------------------------------------------------------------------
-- §42 Gathering Feel: gathering nodes are struck, not prompted. Left click /
-- tap (or hold) a node, or the Attack button / ButtonR2 with no creature in
-- reach: the held tool swings (IsleGestureLocal: pickaxe overhead strike,
-- hatchet side chop, hoe chop; animate.client.lua auto-holds the best owned
-- tool), and at the swing's impact frame (Data.Strike.IMPACT) one
-- IsleAction("strike", <node host>) goes to the server, which validates and
-- applies its own damage. The reply paints a pooled hitsplat and the node's
-- overhead bar (YOUR progress: nodes are per player), the break hands the node
-- to gather.client.lua to deplete locally (IsleNodeDepleted:Fire(node, s)).
-- Fishing: a click casts (the rod's cast gesture holds); the fish bites after
-- the server's delay (a "!" splat, the bar flashes "Bite!"); a click inside the
-- window reels. The local cadence mirrors the server's (Data.Strike.SWING).
------------------------------------------------------------------------------
do
	local GN = {next = 0, held = nil, target = nil, fish = nil, sent = 0, buffered = nil, nodes = {}, nearAt = -math.huge, near = nil}
	S.gather = GN
	local ST = Data and Data.Strike
	GN.BUFFER = 0.25 -- QC L16: a tap this close to the next swing is kept and swung on time
	local function bindable(name)
		local e = ReplicatedStorage:FindFirstChild(name)
		if not e then e = make("BindableEvent", ReplicatedStorage, {Name = name}) end
		return e
	end
	GN.depleted = bindable("IsleNodeDepleted") -- (node, regrowSeconds): gather.client.lua depletes it locally
	GN.skillEvent = bindable("IsleGatherSkill") -- (skill): the hotbar's context tool
	-- QC L14: the tagged node list is cached (kept by the tag signals), not
	-- fetched every frame.
	do
		local function add(node) if not table.find(GN.nodes, node) then table.insert(GN.nodes, node) end end
		for _, node in ipairs(CollectionService:GetTagged("AetherNode")) do add(node) end
		pcall(function()
			CollectionService:GetInstanceAddedSignal("AetherNode"):Connect(add)
			CollectionService:GetInstanceRemovedSignal("AetherNode"):Connect(function(node)
				local i = table.find(GN.nodes, node)
				if i then table.remove(GN.nodes, i) end
			end)
		end)
	end
	-- The node host (a BasePart carrying GatherNode) under a hit part, walking up
	-- to its visual Model (≤ 6 levels).
	function GN.hostOf(part)
		local node = part
		for _ = 1, 6 do
			if not node or node == Workspace then return nil end
			if node:IsA("BasePart") and type(node:GetAttribute("GatherNode")) == "string" then return node end
			if node:IsA("Model") then
				for _, child in ipairs(node:GetChildren()) do
					if child:IsA("BasePart") and type(child:GetAttribute("GatherNode")) == "string" then return child end
				end
			end
			node = node.Parent
		end
		return nil
	end
	function GN.resource(node)
		return ST and node and ST.resource(node:GetAttribute("GatherNode")) or nil
	end
	-- Locally depleted (gather.client.lua's per-player state): seconds left, or 0.
	function GN.respawnLeft(node)
		local api = ReplicatedStorage:FindFirstChild("IsleNodeState")
		if not api or not api:IsA("BindableFunction") then return 0 end
		local ok, left = pcall(function() return api:Invoke(node) end)
		return if ok and type(left) == "number" then left else 0
	end
	function GN.usable(node)
		if not node or not node.Parent or not GN.resource(node) then return false end
		local owner = node:GetAttribute("OwnerUserId")
		return owner == nil or owner == player.UserId
	end
	function GN.reach(node)
		local r = GN.resource(node)
		return if r and r.skill == "Fishing" then ST.FISH_REACH else (ST and ST.REACH or 10)
	end
	-- Distance to the node's edge, as the server measures it.
	function GN.distance(node)
		local root = rootOf()
		if not root or not node then return math.huge end
		local half = math.min(6, math.max(node.Size.X, node.Size.Z) / 2)
		return (root.Position - node.Position).Magnitude - half
	end
	-- The node under a screen point: the first thing the ray hits (a creature in
	-- front wins: combat attacks it), else the node whose host lies closest to the
	-- ray (small hosts such as crystal anchors stay easy to click).
	local nodeRay = RaycastParams.new()
	nodeRay.FilterType = Enum.RaycastFilterType.Exclude
	function GN.pick(screenPosition)
		local camera = Workspace.CurrentCamera
		if not camera then return nil end
		local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
		nodeRay.FilterDescendantsInstances = {player.Character}
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * 300, nodeRay)
		if hit then
			if monsterFromPart(hit.Instance) then return nil end
			local host = GN.hostOf(hit.Instance)
			if host then return if GN.usable(host) then host else nil end
		end
		local best, bestT = nil, hit and (hit.Position - ray.Origin).Magnitude + 2 or math.huge
		for _, node in ipairs(GN.nodes) do
			if node:IsA("BasePart") and GN.usable(node) then
				local rel = node.Position - ray.Origin
				local t = rel:Dot(ray.Direction)
				if t > 0 and t < bestT and t < 200 then
					local off = (rel - ray.Direction * t).Magnitude
					if off <= math.max(2, math.max(node.Size.X, node.Size.Y, node.Size.Z) / 2 + 0.5) then best, bestT = node, t end
				end
			end
		end
		return best
	end
	-- Nearest usable, standing node in reach (Attack button / gamepad). QC L14:
	-- the scan runs at most 10 times a second (`fresh` forces one: a new press).
	function GN.nearest(fresh)
		local now = os.clock()
		local cached = GN.near
		if not fresh and now - GN.nearAt < 0.1 and (cached == nil or GN.usable(cached)) then return cached end
		GN.nearAt = now
		local best, bestD = nil, math.huge
		for _, node in ipairs(GN.nodes) do
			if node:IsA("BasePart") and GN.usable(node) then
				local d = GN.distance(node)
				if d <= GN.reach(node) and d < bestD and GN.respawnLeft(node) <= 0 then best, bestD = node, d end
			end
		end
		GN.near = best
		return best
	end
	function GN.caption(r) return r.skill .. " " .. r.level end
	function GN.top(node) return node.Position + Vector3.new(0, math.min(4, node.Size.Y / 2) + 1, 0) end
	local function gesture(name, node, mode)
		local g = ReplicatedStorage:FindFirstChild("IsleGestureLocal")
		if g then g:Fire(name, node, nil, mode) end
	end
	-- QC L15: one reused Highlight for node hit flashes (never one per node).
	function GN.flash(model)
		if not model or not model.Parent then return end
		local h = GN.highlight
		if not h then
			h = make("Highlight", nil, {Name = "NodeHitFlash", FillColor = Color3.new(1, 1, 1), FillTransparency = 1, OutlineTransparency = 1,
				DepthMode = Enum.HighlightDepthMode.Occluded, Enabled = false})
			GN.highlight = h
		end
		GN.flashToken = (GN.flashToken or 0) + 1
		local token = GN.flashToken
		h.Adornee = model
		h.Parent = Workspace.CurrentCamera
		h.Enabled = true
		h.FillTransparency = 0.35
		TweenService:Create(h, TweenInfo.new(0.18), {FillTransparency = 1}):Play()
		task.delay(0.2, function()
			if GN.flashToken ~= token then return end
			h.Enabled = false
			h.Adornee = nil
		end)
	end
	function GN.endFish()
		local fish = GN.fish
		GN.fish = nil
		if fish then gesture("release") end
		return fish
	end
	-- QC L1: the server pushes the bite when it happens (IsleStrike "bite").
	function GN.onBite(kind, node, window)
		local fish = GN.fish
		if kind ~= "bite" or not fish or fish.node ~= node or fish.biting then return end
		fish.biting = true
		window = tonumber(window) or (ST and ST.FISH.window) or 1.2
		SP.show(GN.top(node), {kind = "text", text = "!", ink = gold, size = 30}, node)
		OB.touchNode(node, 1, 1, "Bite!")
		task.delay(window + 0.35, function()
			if GN.fish ~= fish then return end
			GN.endFish()
			toast("It got away.")
			OB.release(node)
		end)
	end
	do
		local function bindBite(remote)
			if GN.biteBound or not remote or not remote:IsA("RemoteEvent") then return end
			GN.biteBound = true
			remote.OnClientEvent:Connect(GN.onBite)
		end
		bindBite(ReplicatedStorage:FindFirstChild("IsleStrike"))
		if not GN.biteBound then
			pcall(function() ReplicatedStorage.ChildAdded:Connect(function(c) if c.Name == "IsleStrike" then bindBite(c) end end) end)
		end
	end
	function GN.onReply(node, reply)
		if type(reply) ~= "table" or not reply.strike then return end
		local r = GN.resource(node)
		if not r then return end
		if reply.ok == false then
			if reply.reason == "cadence" then GN.next = os.clock() + math.max(0.05, tonumber(reply.wait) or 0.1) return end
			if reply.reason == "regrowing" and tonumber(reply.regrow) then GN.depleted:Fire(node, tonumber(reply.regrow)) end
			if reply.reason == "early" then GN.endFish() end
			if reply.reason == "harvest" and tonumber(reply.hp) and tonumber(reply.max) then OB.touchNode(node, tonumber(reply.hp), tonumber(reply.max), GN.caption(r)) end
			-- The server pushed refusals with a message as a snapshot (chat + toast); others toast here.
			if reply.message and not reply.pushed then toast(reply.message) end
			if reply.reason ~= "busy" then GN.target, GN.buffered = nil, nil end
			return
		end
		if reply.cast then
			-- No bite time is sent (QC L1): wait for the server's push; give up
			-- after the longest bite plus the window.
			local F = ST.FISH
			local fish = {node = node, at = os.clock()}
			GN.fish = fish
			OB.touchNode(node, 0, 1, "Waiting…")
			task.delay(F.biteMax + F.window + F.late + 0.5, function()
				if GN.fish ~= fish or fish.biting then return end
				GN.endFish()
				toast("It got away.")
				OB.release(node)
			end)
			return
		end
		if tonumber(reply.dmg) then
			SP.show(GN.top(node), HD.splatStyle({amount = reply.dmg}, Theme), node)
			GN.flash(node.Parent and node.Parent:IsA("Model") and node.Parent or node)
		end
		if reply.broken then
			GN.endFish()
			OB.touchNode(node, 0, math.max(1, tonumber(reply.max) or 1), GN.caption(r))
			OB.release(node)
			GN.depleted:Fire(node, tonumber(reply.regrow) or r.respawn)
			-- QC L13: a break ends the hold; nothing auto-retargets another node.
			GN.target, GN.held, GN.buffered = nil, nil, nil
		elseif tonumber(reply.hp) and tonumber(reply.max) then
			OB.touchNode(node, tonumber(reply.hp), tonumber(reply.max), GN.caption(r))
		end
	end
	-- Sends one strike (yields on the remote in its own thread).
	function GN.send(node)
		local remote = ReplicatedStorage:FindFirstChild("IsleAction")
		if not remote or not node.Parent then return end
		GN.sent += 1
		task.spawn(function()
			local ok, reply = pcall(function() return remote:InvokeServer("strike", node) end)
			if ok then GN.onReply(node, reply) end
		end)
	end
	-- QC M2: out of reach, walk up along the overlay's pathfinding route
	-- (S.walkPath: ≤ S.WALK_MAX studs, every waypoint over ground, else a "Too
	-- far" / "can't reach" toast) and swing on arrival (IsleAttackLocal). Never a
	-- straight MoveTo across the void.
	function GN.walkUp(node)
		local walk = ReplicatedStorage:FindFirstChild("IsleWalkLocal")
		if not walk or not walk:IsA("BindableFunction") then toast("Too far: walk closer first.") return end
		task.spawn(function() pcall(function() walk:Invoke("node", node, GN.reach(node)) end) end)
	end
	function GN.stopWalk()
		local walk = ReplicatedStorage:FindFirstChild("IsleWalkLocal")
		if walk and walk:IsA("BindableFunction") then pcall(function() walk:Invoke("cancel") end) end
	end
	-- One swing at `node` (or a walk into reach first). `auto`: the hold loop or
	-- a buffered tap (never walks: QC L13). Returns true when a swing started.
	function GN.strike(node, auto)
		if not ST or not alive() or not GN.usable(node) or player:GetAttribute("IslandBuilding") == true then return false end
		local r = GN.resource(node)
		local now = os.clock()
		if GN.distance(node) > GN.reach(node) then
			if not auto and not GN.held then GN.walkUp(node) end
			return false
		end
		if not auto then GN.stopWalk() end
		if r.skill == "Fishing" then
			local fish = GN.fish
			if fish and fish.node == node then
				-- Reel: the click is the strike (no wind-up), early or not; the server judges.
				GN.fish = nil
				gesture("release")
				GN.send(node)
				return true
			end
			if now < GN.next then return false end
			GN.next = now + ST.FISH.gap
			gesture("fish", node, "hold")
			GN.skillEvent:Fire(r.skill)
			GN.send(node)
			return true
		end
		if GN.respawnLeft(node) > 0 then return false end
		if now < GN.next then
			-- QC L16: a tap just before the swing is ready is kept, not dropped.
			if GN.next - now <= GN.BUFFER then GN.buffered = node end
			return false
		end
		GN.buffered = nil
		-- QC H1: one gathering clock; striking another node drops a cast.
		local fish = GN.endFish()
		if fish then OB.release(fish.node) end
		GN.next = now + (ST.SWING[r.skill] or 0.7)
		GN.target = node
		gesture(ST.GESTURE[r.skill] or "mine", node)
		GN.skillEvent:Fire(r.skill)
		task.delay(ST.IMPACT[r.skill] or 0.4, function() GN.send(node) end)
		return true
	end
	-- QC M4: with a line in the water, R2 / the Attack button reel that spot.
	function GN.padTarget()
		local fish = GN.fish
		if fish and GN.usable(fish.node) then return fish.node end
		return GN.nearest(true)
	end
	-- Input: creatures stay combat's (the handlers above); a node takes the click
	-- when no creature is under the cursor / in reach.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if pick(input.Position) then return end
			local node = GN.pick(input.Position)
			if node then
				S.pendingAttack = nil
				GN.target = node
				GN.strike(node)
				GN.held = "mouse"
			end
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			if nearestMonster(true) then return end
			local node = GN.padTarget()
			if node then GN.strike(node) end
			GN.held = "pad"
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.MouseButton1 and GN.held == "mouse")
			or (input.KeyCode == Enum.KeyCode.ButtonR2 and GN.held == "pad") then
			GN.held = nil
		end
	end)
	-- QC L13: a release the window never sees (alt-tab) must not leave the hold on.
	pcall(function() UserInputService.WindowFocusReleased:Connect(function() GN.held, GN.buffered = nil, nil end) end)
	UserInputService.TouchTapInWorld:Connect(function(position, processed)
		if processed or pick(position) then return end
		local node = GN.pick(position)
		if node then GN.strike(node) end
	end)
	if attackButton then
		attackButton.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
			if nearestMonster(true) then return end
			local node = GN.padTarget()
			if node then GN.strike(node) end
			GN.held = "button"
		end)
		attackButton.InputEnded:Connect(function(input)
			if (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1) and GN.held == "button" then GN.held = nil end
		end)
	end
	-- §34 menu / overlay: IsleAttackLocal:Fire(node host) strikes it (walking up first).
	local attackLocal = ReplicatedStorage:FindFirstChild("IsleAttackLocal")
	if attackLocal then
		attackLocal.Event:Connect(function(model)
			if model == "cancel" then return end
			if typeof(model) == "Instance" and model:IsA("BasePart") and GN.resource(model) then
				GN.target = model
				GN.strike(model)
			end
		end)
	end
	-- Holding keeps swinging at the cadence at the node it started on (the pad
	-- and the button find the nearest standing node only until a swing starts);
	-- a buffered tap swings when the cadence allows.
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local buffered = GN.buffered
		if buffered and now >= GN.next then
			GN.buffered = nil
			if GN.usable(buffered) then GN.strike(buffered, true) end
		end
		if not GN.held or GN.fish then return end
		local node = if GN.held == "mouse" then GN.target else (GN.target or GN.nearest())
		if node and GN.resource(node) and GN.resource(node).skill ~= "Fishing" and now >= GN.next then GN.strike(node, true) end
	end)
end

-- Test / tooling handle (no gameplay effect): the splat and bar pools.
do
	local api = Instance.new("BindableFunction")
	api.Name = "IsleCombatApi"
	api.OnInvoke = function(method)
		if method == "state" then return S end
		return nil
	end
	api.Parent = player
end
