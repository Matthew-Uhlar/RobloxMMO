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
local deep, ivory, gold, mint = rgb("0C1820"), rgb("F7EFDC"), rgb("F3C66E"), rgb("7FE3CC")
local brass, brassDark, track, ember, raised = rgb("C9974A"), rgb("6B4E24"), rgb("060E14"), rgb("EF7D67"), rgb("2A4D5E")
local heavy, display = Enum.Font.BuilderSansExtraBold, Enum.Font.FredokaOne
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
--   tutorial tracker (npc.client.lua)  left column   x 10-260, y 100-166
--   Wayfinder minimap (nav.client.lua) top-right     SIZE 118 (viewport < 520 tall) or 156,
--                                                    x W-10-SIZE..W-10, y 8..SIZE+42
--   top lane between them (x 325..W-SIZE-20): target/boss panel y 10-68,
--   event banner y 76-110, Wayfinder toast y 118-158.
-- Items centre on the screen when they fit the lane, else centre in the lane
-- (shrunk to it). Screens whose lane is under 220 px stack below the tracker.
local HUD_RIGHT, EDGE, BELOW_HUD = 325, 10, 174
local function laneFor(width)
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize
	local height = if viewport and viewport.Y > 0 then viewport.Y else (gui.AbsoluteSize and gui.AbsoluteSize.Y or 720)
	local mapSize = if height < 520 then 118 else 156
	return HUD_RIGHT, width - EDGE - mapSize - EDGE
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
		-- Very narrow: stack in the left column under the tutorial tracker.
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
		Name = "AttackButton", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -110, 1, -40),
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
		BackgroundColor3 = gold, Font = heavy, TextSize = 10, TextColor3 = deep, Text = tostring(i), BorderSizePixel = 0, ZIndex = 4,
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
	-- Touch: left of the Attack button (x W-188..W-110); else the bottom-right corner.
	spellBar.Position = if attackButton then UDim2.new(1, -196, 1, -44) else UDim2.new(1, -10, 1, -44)
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
	local lift = if shown then size + 6 else 0
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
	target = model
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
-- Spell bar slot i (keys 1-6, taps, gamepad L1 on the cursor).
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
-- keys 1-6 cast spell slots, DPad cycles the cursor and L1 casts it.
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
local SLOT_KEYS = {[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6}
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
floatText = function(position, text, color, size)
	local anchor = make("Attachment", Workspace.Terrain, {
		WorldPosition = position + Vector3.new((math.random() - 0.5) * 2, math.random() * 0.8, (math.random() - 0.5) * 2),
	})
	local board = make("BillboardGui", anchor, {
		Size = UDim2.fromOffset(160, 44), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 120,
	})
	local label = make("TextLabel", board, {
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = bold, TextSize = size, RichText = true,
		TextColor3 = color, TextStrokeTransparency = 0.2, TextStrokeColor3 = deep, Text = text,
	})
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(board, info, {StudsOffsetWorldSpace = Vector3.new(0, 3, 0)}):Play()
	TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.45), {
		TextTransparency = 1, TextStrokeTransparency = 1,
	}):Play()
	task.delay(1, function() anchor:Destroy() end)
end
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
		local amount = tonumber(payload.amount) or 0
		if payload.miss then
			floatText(payload.position, "miss", rgb("A9BDC1"), 17)
		else
			local text, color, size = commas(amount), Color3.new(1, 1, 1), 20
			if payload.crit then text, color, size = "✧ " .. text .. " ✧", gold, 26 end
			-- Triangle tags: WEAK! in gold, resist in grey.
			if payload.tag == "weak" then
				text, size = text .. ' <font color="#FFD24A" size="' .. (size - 4) .. '">WEAK!</font>', size + 2
			elseif payload.tag == "resist" then
				text = text .. ' <font color="#A9BDC1" size="' .. (size - 6) .. '">resist</font>'
				if not payload.crit then color = rgb("D5DDDF") end
			end
			floatText(payload.position, text, color, size)
			if typeof(payload.model) == "Instance" then flash(payload.model) end
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
		if root then floatText(root.Position + Vector3.new(0, 2.5, 0), "-" .. commas(tonumber(payload.amount) or 0), rgb("FF6B5B"), 18) end
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
-- Places the bar in the top lane (or under the tutorial tracker on narrow
-- screens) and the board under the minimap when the screen is tall enough.
function WBH.layout()
	local view = gui.AbsoluteSize
	local width = if view and view.X > 0 then view.X else 1280
	local height = if view and view.Y > 0 then view.Y else 720
	if not placeInLane(WBH.bar, 380, EDGE, WBH.BAR_HEIGHT, width) then
		local _, right = laneFor(width)
		WBH.bar.AnchorPoint, WBH.bar.Position = Vector2.new(0, 0), UDim2.fromOffset(EDGE, BELOW_HUD)
		WBH.bar.Size = UDim2.fromOffset(math.max(160, math.min(380, right - EDGE)), WBH.BAR_HEIGHT)
	end
	local mapSize = if height < 520 then 118 else 156
	WBH.tall = height >= 520
	WBH.board.Position = UDim2.new(1, -EDGE, 0, mapSize + 42 + 8)
	WBH.board.Size = UDim2.fromOffset(math.max(150, mapSize + 20), 126)
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
		bar.Position = if attackButton then UDim2.new(1, -196, 1, -44 - size - 6) else UDim2.new(1, -10, 1, -44 - size - 6)
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
		local model = if held == "mouse" then target else nearestMonster()
		if model then tryAttack(model) end
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
