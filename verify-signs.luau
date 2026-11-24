-- Signs (docs/DEPTH-CONTRACT.md §28): every sign in the generated world goes
-- through the shared Signs system in world.server.lua. Builds the real world
-- (static islands plus a home island with its garden, crew haven and builder's
-- terrace) and checks: one invisible anchor (or ledger board) per sign, the
-- billboard vocabulary and its full / compact forms, the static part budget,
-- no lights, no posts or poles near a sign, text that fits its box (independent
-- re-measure) and renders >= 10 px at every distance on phone and desktop,
-- night readability, fonts, arrows, prompts; the on-screen footprint (no
-- overlaps, clusters readable side by side) at 844x390 and 1920x1080; wall
-- clipping from 8 headings; the SignView rules; and signs.client.lua itself
-- run against engine mocks.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame, Color3 = roblox.Vector3, roblox.CFrame, roblox.Color3
local checks = 0
local function ok(cond, case) assert(cond, case); checks += 1 end
local function signal()
	local listeners = {}
	return {
		Connect = function(_, f)
			local c = {Connected = true}
			function c:Disconnect() self.Connected = false end
			table.insert(listeners, {f, c})
			return c
		end,
		Fire = function(_, ...) for _, l in listeners do if l[2].Connected then l[1](...) end end end,
	}
end
local promptSignals = {}
roblox.implementProperty("ProximityPrompt", "Triggered", function(prompt)
	if not promptSignals[prompt] then promptSignals[prompt] = signal() end
	return promptSignals[prompt]
end)
roblox.implementProperty("ProximityPrompt", "Destroying", function(prompt)
	return signal()
end)
-- Per-instance engine events the sign code listens to (Model streaming and
-- Destroying), fired by hand below.
local instanceSignals = {}
local function instanceSignal(obj, name)
	instanceSignals[obj] = instanceSignals[obj] or {}
	if not instanceSignals[obj][name] then instanceSignals[obj][name] = signal() end
	return instanceSignals[obj][name]
end
for _, event in {"Destroying", "DescendantAdded", "DescendantRemoving"} do
	roblox.implementProperty("Model", event, function(m) return instanceSignal(m, event) end)
end
local Data = luau.load(fs.readFile("shared/GameData.lua"), {injectGlobals = true})()
local World = luau.load(fs.readFile("art/WorldCatalog.lua"), {injectGlobals = true})()
local Props = luau.load(fs.readFile("art/PropCatalog.lua"), {injectGlobals = true})()
local world = roblox.Instance.new("Workspace")
local dataModule = {Name = "AetherData"}
local players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end}
local tags = {}
local env = {
	game = {GetService = function(_, name)
		if name == "Players" then return players end
		if name == "Lighting" then return roblox.Instance.new("Lighting") end
		if name == "CollectionService" then return {AddTag = function(_, obj, tag) tags[tag] = tags[tag] or {}; table.insert(tags[tag], obj) end} end
		if name == "ReplicatedStorage" then return {WaitForChild = function(_, n) return if n == "AetherData" then dataModule else nil end} end
		if name == "ServerStorage" then return {FindFirstChild = function() return nil end} end
		return {}
	end},
	workspace = world, Instance = roblox.Instance, Vector3 = Vector3, Vector2 = roblox.Vector2, CFrame = CFrame, Color3 = Color3,
	UDim2 = roblox.UDim2, UDim = roblox.UDim, Font = roblox.Font, Enum = roblox.Enum, NumberRange = roblox.NumberRange,
	NumberSequence = roblox.NumberSequence, ColorSequence = roblox.ColorSequence,
	task = {spawn = function() end, wait = function() end, defer = function() end, delay = function() end},
	require = function(module) assert(module == dataModule, "world requires only AetherData") return Data end,
}
local source = fs.readFile("world.server.lua")
luau.load(source:gsub("plans%.Position", "plans.CFrame.Position"), {environment = env, injectGlobals = true})()
local islands = world:FindFirstChild("Islands")
local archipelago = world:FindFirstChild("AetherIsles")
ok(islands ~= nil and archipelago ~= nil, "world built")

-- Static budget is counted before any player arrives.
local staticParts, signParts, staticSigns = 0, 0, 0
for _, obj in world:GetDescendants() do
	if obj:IsA("BasePart") then
		staticParts += 1
		local holder = obj.Parent
		while holder and holder ~= world and holder:GetAttribute("SignArchetype") == nil do holder = holder.Parent end
		if holder and holder ~= world then signParts += 1 end
	elseif obj:IsA("Model") and obj:GetAttribute("SignArchetype") then
		staticSigns += 1
	end
end
ok(staticParts < 4000, "static world stays under the 4000 part budget (" .. staticParts .. ")")

-- A home island (garden, deck, crew haven, builder's terrace) brings the home signs.
local function player(id, attributes)
	local changed = {}
	local p = {UserId = id, Name = "P" .. id, CharacterAdded = signal(), attributes = attributes or {}}
	function p:GetAttribute(key) return self.attributes[key] end
	function p:GetAttributeChangedSignal(key) changed[key] = changed[key] or signal(); return changed[key] end
	function p:SetAttribute(key, value) self.attributes[key] = value; self:GetAttributeChangedSignal(key):Fire() end
	players.PlayerAdded:Fire(p)
	return p
end
local guest = player(77, {HomeGarden = true, HomeDeck = true, Worker1Tier = 1})
pcall(function() guest:SetAttribute("CoopId", "7") end)
pcall(function() guest:SetAttribute("GardenUnlocked", true) end)

------------------------------------------------------------------------------
-- Independent text measure (same rules as the docs: conservative em widths).
------------------------------------------------------------------------------
local EM = {W = 1.0, M = .96, m = .88, w = .8, [" "] = .3, i = .34, l = .34, j = .34, I = .44, t = .42, f = .42, r = .46, ["."] = .32,
	[","] = .32, ["'"] = .28, ["•"] = .5, ["/"] = .44, ["-"] = .44, ["+"] = .64, ["·"] = .36}
local function width(text, size)
	local em = 0
	for _, code in utf8.codes(text) do
		local ch = utf8.char(code)
		em += EM[ch] or (if ch:match("^%u$") then .76 elseif ch:match("^%l$") then .6 elseif ch:match("^%d$") then .66 else .56)
	end
	return em * size
end
local function lines(text, size, w)
	local n, line = 1, ""
	for word in text:gmatch("%S+") do
		local candidate = if line == "" then word else line .. " " .. word
		if line ~= "" and width(candidate, size) > w then n += 1; line = word else line = candidate end
		if width(word, size) > w then return math.huge end
	end
	return n
end
local function luminance(c)
	local function ch(v) return if v <= .03928 then v / 12.92 else ((v + .055) / 1.055) ^ 2.4 end
	return .2126 * ch(c.R) + .7152 * ch(c.G) + .0722 * ch(c.B)
end
local function contrast(a, b)
	local la, lb = luminance(a), luminance(b)
	return (math.max(la, lb) + .05) / (math.min(la, lb) + .05)
end
-- Colours a frame really shows: a UIGradient multiplies the background, so a
-- graded frame is white and its keypoints are the true colours.
local function shown(frame)
	local g = frame:FindFirstChildOfClass("UIGradient")
	if not g then return {frame.BackgroundColor3} end
	local out = {}
	for _, k in g.Color.Keypoints do
		local c, b = k.Value, frame.BackgroundColor3
		table.insert(out, Color3.new(c.R * b.R, c.G * b.G, c.B * b.B))
	end
	return out
end
local function worst(color, frame)
	local r = math.huge
	for _, c in shown(frame) do r = math.min(r, contrast(color, c)) end
	return r
end
local function stripTags(text) return (text:gsub("<[^>]->", ""):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")) end

------------------------------------------------------------------------------
-- Sign models (§28 v2): one invisible anchor, one floating billboard, no
-- posts, frames, plinths or sign meshes. Ledgers are a notice board (both
-- faces) with a floating title billboard.
------------------------------------------------------------------------------
local View = luau.load(fs.readFile("shared/SignView.lua"), {environment = {Vector3 = Vector3}, injectGlobals = true})()
local KINDS = {hanging = true, shop = true, post = true, banner = true, plaque = true, ledger = true}
local FONTS = {["rbxasset://fonts/families/Merriweather.json"] = true, ["rbxasset://fonts/families/BuilderSans.json"] = true,
	["rbxasset://fonts/families/Fondamento.json"] = true}
local TITLE_FONTS = {["rbxasset://fonts/families/Merriweather.json"] = true, ["rbxasset://fonts/families/Fondamento.json"] = true}
local signs, kinds, boards = {}, {}, {}
local guiInstances, labelCount, billboards = 0, 0, 0
local function collectSigns()
	local out = {}
	for _, model in world:GetDescendants() do
		if model:IsA("Model") and model:GetAttribute("SignArchetype") then table.insert(out, model) end
	end
	return out
end
for _, model in collectSigns() do
	local kind = model:GetAttribute("SignArchetype")
	table.insert(signs, model)
	ok(KINDS[kind], model:GetFullName() .. " archetype " .. tostring(kind))
	ok(model.Name == "Sign " .. model:GetAttribute("SignTitle"), model:GetFullName() .. " keeps the Sign <title> name")
	ok(model:GetAttribute("SignVersion") == 2, model:GetFullName() .. " is a v2 sign")
	-- QC L3: a sign streams in as one unit (anchor and billboard together).
	local readable, mode = pcall(function() return model.ModelStreamingMode end)
	if readable then ok(mode == roblox.Enum.ModelStreamingMode.Atomic, model:GetFullName() .. " streams atomically") end
	kinds[kind] = (kinds[kind] or 0) + 1
	local parts = {}
	for _, p in model:GetDescendants() do
		ok(not p:IsA("Light"), model:GetFullName() .. " adds no lights")
		if p:IsA("BasePart") then table.insert(parts, p) end
	end
	ok(#parts == 1, model:GetFullName() .. " is a single part (" .. #parts .. "): no posts, brackets, plinths or frames")
	local p = parts[1]
	ok(not p.CanCollide and not p.CanTouch, p:GetFullName() .. " never blocks a path")
	ok(p:GetAttribute("ShapeBox") == nil, p:GetFullName() .. " has no declared frame box")
	local guis = {}
	for _, g in p:GetChildren() do if g:IsA("BillboardGui") then table.insert(guis, g) end end
	ok(#guis == 1 and guis[1].Name == "SignBillboard", model:GetFullName() .. " carries one SignBillboard")
	if kind == "ledger" then
		-- QC M3: both faces carry the rows; a camera-facing title floats above.
		local front, back = p:FindFirstChild("Sign face Front"), p:FindFirstChild("Sign face Back")
		ok(p:GetAttribute("Shape") == "SignNoticeBoard" and front and back and front:IsA("SurfaceGui") and back:IsA("SurfaceGui"),
			model:GetFullName() .. " ledger board with a front and a back face")
		ok(front.Face == roblox.Enum.NormalId.Front and back.Face == roblox.Enum.NormalId.Back, model:GetFullName() .. " faces on both sides")
		for _, d in front:GetDescendants() do
			if d:IsA("TextLabel") then
				local twin = back:FindFirstChild(d.Name, true)
				ok(twin and twin.Text == d.Text, d.Name .. " mirrored on the back face of " .. model.Name)
			end
		end
		ok(guis[1].StudsOffsetWorldSpace.Y > p.Size.Y / 2 + 1, model:GetFullName() .. " title floats above the board")
		ok(guis[1]:GetAttribute("SignKind") == "ledger", model:GetFullName() .. " title billboard kind")
	else
		ok(p:GetAttribute("SignAnchor") == true and p.Transparency == 1 and not p.CanQuery and p:GetAttribute("Shape") == nil,
			p:GetFullName() .. " is an invisible, mesh-free anchor")
		ok(p.Name == model:GetAttribute("SignTitle"), p:GetFullName() .. " anchor is named after the title (returned main part)")
	end
	table.insert(boards, {model = model, kind = kind, anchor = p, gui = guis[1]})
end
ok(#tags.AetherSign == #signs, "every sign is tagged AetherSign")
for kind in KINDS do ok((kinds[kind] or 0) >= 1, kind .. " archetype is used in the world") end
ok(#signs >= 80, "signs across the world (" .. #signs .. ")")

------------------------------------------------------------------------------
-- Billboard style: framed, themed, distinct from NPC nameplates, readable.
------------------------------------------------------------------------------
local npcSource = fs.readFile("npc.server.lua")
ok(npcSource:find('"Nameplate"', 1, true) and npcSource:find("GothamBold", 1, true), "NPC nameplates: a dark Gotham strip named Nameplate")
local function find(root, name) return root:FindFirstChild(name) end
-- Which forms a label renders in: "full" (scale >= DETAIL), "compact" or both.
local function formsOf(label, gui)
	local node, inDetail, rootName = label, false, nil
	while node and node ~= gui do
		if node.Name == "Detail" then inDetail = true end
		if node.Parent == gui then rootName = node.Name end
		node = node.Parent
	end
	if rootName == "Compact" then return {compact = true} end
	if inDetail or gui:FindFirstChild("Compact") then return {full = true} end
	return {full = true, compact = true}
end
local minRendered = math.huge
for _, b in boards do
	local gui, kind, name = b.gui, b.kind, b.model:GetFullName()
	billboards += 1
	ok(gui.Name ~= "Nameplate", name .. " is not a nameplate")
	ok(not gui.AlwaysOnTop, name .. " never shows through walls")
	ok(gui.MaxDistance == (if kind == "plaque" then 160 else 120), name .. " MaxDistance by archetype (" .. gui.MaxDistance .. ")")
	ok(gui.LightInfluence <= .25 and gui.Brightness >= 1, name .. " self-lights for night reading")
	ok(gui.Size.X.Scale == 0 and gui.Size.Y.Scale == 0 and gui.Size.X.Offset <= 440 and gui.Size.Y.Offset <= 400, name .. " has a bounded design size")
	ok(gui:GetAttribute("SignStyled") == true and gui:GetAttribute("SignKind") == kind, name .. " styled for its archetype")
	local lift = gui:GetAttribute("SignLift")
	ok(type(lift) == "number" and math.abs(gui.StudsOffsetWorldSpace.Y - lift) < 1e-4 and lift >= 2 and lift <= 10, name .. " floats above its anchor")
	local full, compact = gui:GetAttribute("SignFull"), gui:GetAttribute("SignCompact")
	ok(typeof(full) == "Vector2" and typeof(compact) == "Vector2" and compact.Y <= full.Y and compact.X <= full.X
		and full.X <= gui.Size.X.Offset and full.Y <= gui.Size.Y.Offset, name .. " declares its full and compact boxes")
	local root = gui:FindFirstChild("Sign")
	ok(root and root.ClassName == "CanvasGroup" and root:FindFirstChildOfClass("UIScale") ~= nil, name .. " root fades (CanvasGroup) and scales (UIScale)")
	-- Ornate plaque vocabulary (absent from NPC nameplates).
	for _, piece in {"Frame", "Panel", "Inlay", "Shadow", "Crest", "Crest glyph", "Crystal", "Crystal glow"} do
		ok(find(root, piece) ~= nil, name .. " has its " .. piece)
	end
	local glow = find(root, "Crystal glow")
	ok(glow:GetAttribute("NightTransparency") < glow:GetAttribute("DayTransparency"), name .. " crystal glows brighter at night")
	for _, c in shown(find(root, "Frame")) do ok(c ~= Color3.fromHex("091923") and c ~= Color3.new(1, 1, 1), name .. " frame is graded metal, not the nameplate ink") end
	if kind ~= "banner" then
		local caps = 0
		for _, c in root:GetChildren() do if c.Name == "Corner cap" then caps += 1 end end
		ok(caps == 4, name .. " has four corner caps")
	else
		-- QC H1: banners have a short title-only pennant for the compact form.
		local short = gui:FindFirstChild("Compact")
		ok(short and short.ClassName == "CanvasGroup" and short:FindFirstChildOfClass("UIScale") and short:FindFirstChild("Title") and not short:FindFirstChild("Kicker")
			and not short.Visible, name .. " compact pennant (hidden until compact)")
		ok(compact.Y <= full.Y * .7, name .. " compact pennant is much shorter (" .. compact.Y .. " vs " .. full.Y .. ")")
	end
	local detail = root:FindFirstChild("Detail")
	if detail then
		ok(detail:FindFirstChild("Kicker") and detail:FindFirstChild("Divider"), name .. " detail layer holds the kicker and the divider")
		ok(detail.Position.X.Offset == 0 and detail.Position.Y.Offset == 0, name .. " detail layer shares the root's coordinates")
	end
	ok(not root:FindFirstChild("Kicker") and not root:FindFirstChild("Divider"), name .. " kicker and divider only in the detail layer")
	local glyph = find(root, "Crest glyph")
	ok(glyph.Text ~= "", name .. " crest glyph painted")
	if kind == "shop" then ok(glyph.Text ~= "✦", name .. " shop crest shows its trade glyph") end
	local titles, arrowsN, destinations = 0, 0, 0
	local cw, ch = gui.Size.X.Offset, gui.Size.Y.Offset
	for _, d in gui:GetDescendants() do
		guiInstances += 1
		if d:IsA("GuiObject") and typeof(d:GetAttribute("SignArrowTo")) == "Vector3" then
			arrowsN += 1
			ok(d.Name == "Arrow" and d:FindFirstChild("Head") and d:FindFirstChild("Shaft"), d:GetFullName() .. " arrow glyph")
			local to = d:GetAttribute("SignArrowTo")
			local flat = Vector3.new(to.X - b.anchor.CFrame.Position.X, 0, to.Z - b.anchor.CFrame.Position.Z)
			ok(flat.Magnitude > 3, d:GetFullName() .. " points somewhere else")
		end
		if d:IsA("TextLabel") and d.Name ~= "Crest glyph" and not d.Name:find("Shadow", 1, true) and d.Text ~= "" then
			labelCount += 1
			local w, h, size = d.Size.X.Offset, d.Size.Y.Offset, d.TextSize
			local text = stripTags(d.Text)
			ok(d:GetAttribute("SignPlain") == text, d:GetFullName() .. " plain text recorded ('" .. text .. "')")
			ok(not d.TextScaled and d.TextWrapped and not d.RichText, d:GetFullName() .. " uses a fitted plain text size")
			ok(d:GetAttribute("SignOverflow") == nil, d:GetFullName() .. " '" .. text .. "' fits without overflow")
			ok(FONTS[d.FontFace.Family] == true, d:GetFullName() .. " uses a sign font face")
			local n = lines(text, size, w)
			ok(n <= (d:GetAttribute("SignFitLines") or 1) and n * size * 1.25 <= h + 1, d:GetFullName() .. " '" .. text .. "' fits its box (" .. n .. " lines at " .. size .. "px)")
			ok(d.Position.X.Offset >= 0 and d.Position.Y.Offset >= 0 and d.Position.X.Offset + w <= cw + 1 and d.Position.Y.Offset + h <= ch + 1, d:GetFullName() .. " stays on its plaque")
			local stroke = d:FindFirstChildOfClass("UIStroke") ~= nil
			local shadow = d.Parent:FindFirstChild(d.Name .. "Shadow") ~= nil
			ok(stroke ~= shadow, d:GetFullName() .. " has exactly one outline")
			local on = d.Parent:FindFirstChild(d:GetAttribute("SignOn") or "Panel", true) or d.Parent.Parent:FindFirstChild(d:GetAttribute("SignOn") or "Panel", true)
			ok(on ~= nil, d:GetFullName() .. " names the field it is read on")
			if d.Name == "Title" or d.Name == "Destination" then
				if d.Name == "Title" then titles += 1; ok(TITLE_FONTS[d.FontFace.Family], d:GetFullName() .. " display title font") end
				if d.Name == "Destination" then destinations += 1 end
				ok(worst(d.TextColor3, on) >= 4.5, d:GetFullName() .. " title contrast on its field (night: self-lit)")
			elseif d.Name == "Kicker" then
				ok(worst(d.TextColor3, on) >= 3, d:GetFullName() .. " kicker contrast on " .. on.Name)
			end
			-- QC H2: every label drawn is >= MIN_TEXT rendered px at every
			-- distance up to MaxDistance on both devices, in each form it draws in.
			local forms = formsOf(d, gui)
			for _, phone in {false, true} do
				for dist = 1, gui.MaxDistance, 1 do
					local s = View.scaleFor(dist, phone, kind)
					local form = if View.compact(s) then "compact" else "full"
					if forms[form] then
						local px = size * s
						minRendered = math.min(minRendered, px)
						if px < View.MIN_TEXT then ok(false, d:GetFullName() .. " renders " .. px .. " px at " .. dist .. " studs (" .. (if phone then "phone" else "desktop") .. ")") end
					end
				end
			end
			checks += 1
		end
	end
	if kind == "post" then
		ok(arrowsN >= 1 and arrowsN == destinations, name .. " one arrow per destination (" .. arrowsN .. ")")
	else
		ok(titles == (if kind == "banner" then 2 else 1) and arrowsN == 0, name .. " has its title")
	end
end
ok(minRendered >= View.MIN_TEXT, "smallest rendered sign text " .. minRendered .. " px")
-- Ledger notice boards keep their live rows.
for _, gui in world:GetDescendants() do
	if gui:IsA("SurfaceGui") then
		local holder = gui.Parent and gui.Parent.Parent
		ok(holder and holder:GetAttribute("SignArchetype") == "ledger", gui:GetFullName() .. " SurfaceGuis are only ledger boards")
		ok(gui.MaxDistance >= 80 and not gui.AlwaysOnTop and gui.LightInfluence <= .35, gui:GetFullName() .. " ledger face")
	end
end
for _, name in {"Sign Artificers' Row", "Sign Compass Quay", "Sign Sky Harbor", "Sign Verdant Garden", "Sign Hall of Mastery", "Sign Bestiary", "Sign Commission Board"} do
	ok(world:FindFirstChild(name, true) ~= nil, name .. " exists")
end
ok(world:FindFirstChild("Skill Leaderboard", true):FindFirstChild("Row_" .. Data.SkillOrder[1], true) ~= nil, "ledger rows keep their Row_ names")
ok(world:FindFirstChild("Skill Leaderboard", true):FindFirstChild("Value_" .. Data.SkillOrder[1], true) ~= nil, "ledger rows keep their Value_ names")
-- Faction standards keep their prompt (IsleItem/IsleRegion) on the banner anchor.
local standards = 0
for _, m in world:GetDescendants() do
	if m:IsA("Model") and m:GetAttribute("Faction") then
		local q = m:FindFirstChildWhichIsA("ProximityPrompt", true)
		ok(q and q:GetAttribute("IsleAction") == "factionBoard" and q:GetAttribute("IsleRegion") ~= nil and q.Parent:GetAttribute("SignAnchor") == true
			and q.Parent.Parent:GetAttribute("SignArchetype") == "banner", m.Name .. " standard is a banner sign with its prompt on the anchor")
		standards += 1
	end
end
ok(standards == #Data.Factions.Order, "every faction has a banner standard")
-- QC M1: the Commission Board is one floating sign; its prompt rides the anchor.
do
	local board = world:FindFirstChild("Commission Board", true)
	local holder = board:FindFirstChild("Sign Commission Board")
	local q = holder and holder:FindFirstChildWhichIsA("ProximityPrompt", true)
	ok(q and q:GetAttribute("IsleAction") == "logsBoard" and q:GetAttribute("IsleItem") == "Commissions" and q.Parent:GetAttribute("SignAnchor") == true,
		"Commission Board prompt on the floating sign's anchor")
	for _, p in board:GetDescendants() do
		ok(not (p:IsA("BasePart") and (p.Name:find("post") or p.Name:find("ledger") or p.Name:find("notices") or p:GetAttribute("Shape") == "Signboard")),
			p:GetFullName() .. " no posts or Signboard ledger at the Commission Board")
	end
end
-- QC L5: the agility course banner pole and its cloth are gone.
for _, p in world:GetDescendants() do
	ok(p.Name ~= "Course banner pole" and p.Name ~= "Course banner", p:GetFullName() .. " no agility course banner pole")
end

------------------------------------------------------------------------------
-- No posts anywhere: no part named like a post or pole within 6 studs of a
-- sign anchor (the owner's "get rid of the posts").
------------------------------------------------------------------------------
do
	local anchors = {}
	for _, b in boards do table.insert(anchors, b.anchor.CFrame.Position) end
	local posts = 0
	for _, p in world:GetDescendants() do
		if p:IsA("BasePart") then
			local n = p.Name:lower()
			if n:find("%f[%a]posts?%f[%A]") or n:find("%f[%a]poles?%f[%A]") then
				posts += 1
				local at = p.CFrame.Position
				for i, a in anchors do
					local flat = Vector3.new(at.X - a.X, 0, at.Z - a.Z).Magnitude
					ok(flat >= 6 or math.abs(at.Y - a.Y) > 12, p:GetFullName() .. " (" .. string.format("%.1f", flat) .. " studs) stands clear of " .. boards[i].model:GetFullName())
				end
			end
		end
	end
	ok(posts > 0, "post-like parts exist to check (" .. posts .. ")")
end

------------------------------------------------------------------------------
-- Placement: anchors swallow no foreign prompt; floating plaques never sit on
-- a prompt's screen spot or on each other.
------------------------------------------------------------------------------
local prompts = {}
for _, obj in world:GetDescendants() do
	if obj:IsA("ProximityPrompt") and obj.Parent:IsA("BasePart") then table.insert(prompts, obj) end
end
ok(#prompts > 100, "prompts to check against")
local function inside(model, obj)
	local node = obj
	while node do if node == model then return true end; node = node.Parent end
	return false
end
local function centre(b) return b.anchor.CFrame.Position + Vector3.new(0, b.gui.StudsOffsetWorldSpace.Y, 0) end
local overlaps = {}
for _, b in boards do
	local c = centre(b)
	for _, q in prompts do
		if not inside(b.model, q) then
			local hp = q.Parent.CFrame.Position
			local flat = Vector3.new(hp.X - c.X, 0, hp.Z - c.Z).Magnitude
			ok((hp - b.anchor.CFrame.Position).Magnitude >= .8, b.model:GetFullName() .. " anchor clear of the prompt on " .. q.Parent:GetFullName())
			if not (flat > 2.5 or math.abs(hp.Y - c.Y) > 1.5) then table.insert(overlaps, b.model:GetFullName() .. " covers " .. q.Parent:GetFullName()) end
		end
	end
end
for i, a in boards do
	for j = i + 1, #boards do
		local b = boards[j]
		local ca, cb = centre(a), centre(b)
		if not (Vector3.new(ca.X - cb.X, 0, ca.Z - cb.Z).Magnitude > 3 or math.abs(ca.Y - cb.Y) > 3) then
			table.insert(overlaps, a.model:GetFullName() .. " overlaps " .. b.model:GetFullName())
		end
	end
end
ok(#overlaps == 0, "no plaque covers a prompt or another plaque: " .. table.concat(overlaps, "; "))

------------------------------------------------------------------------------
-- QC H1: on-screen footprint. Each sign is projected (70° vertical FOV) at
-- 844x390 (phone) and 1920x1080 (desktop) through the client pipeline (nearest
-- N, scale band, compact form, declutter): drawn boxes never overlap, and
-- every pair of signs in a cluster (≤ 18 studs apart) reads side by side when
-- the player stands 12 studs in front of the pair.
------------------------------------------------------------------------------
local FOV = 70
local SCREENS = {{name = "phone", size = roblox.Vector2.new(844, 390)}, {name = "desktop", size = roblox.Vector2.new(1920, 1080)}}
local function groundOf(b) return b.anchor.CFrame.Position.Y - (if b.kind == "ledger" then b.anchor.Size.Y / 2 + 1.6 else 2.5) end
-- The client's pipeline for a camera: returns the drawn entries.
local function pipeline(cam, screen, pool)
	local phone = View.isPhone(screen)
	local entries = {}
	for _, b in pool do
		table.insert(entries, {b = b, d = (b.anchor.CFrame.Position - cam.Position).Magnitude, max = b.gui.MaxDistance})
	end
	local chosen = View.select(entries, if phone then View.CAP.phone else View.CAP.desktop)
	for _, e in chosen do
		local s = View.scaleFor(e.d, phone, e.b.kind)
		local compactForm = View.compact(s)
		local x, y, depth = View.project(cam, FOV, screen, centre(e.b))
		if depth > .1 then
			local box = e.b.gui:GetAttribute(if compactForm then "SignCompact" else "SignFull")
			e.rect = View.rect(x, y, box.X, box.Y, if compactForm then e.b.gui:GetAttribute("SignCompactY") else 0, s)
			e.scale, e.depth = s, depth
		end
	end
	View.declutter(chosen)
	local drawn = {}
	for _, e in chosen do if e.clear then table.insert(drawn, e) end end
	return drawn, chosen
end
local function near(b, r)
	local out, c = {}, b.anchor.CFrame.Position
	for _, o in boards do
		local p = o.anchor.CFrame.Position
		if (Vector3.new(p.X - c.X, 0, p.Z - c.Z)).Magnitude <= r and math.abs(p.Y - c.Y) < 40 then table.insert(out, o) end
	end
	return out
end
local footprintViews, clusterPairs, crowded = 0, 0, {}
for _, b in boards do
	local pool = near(b, 170)
	local c = centre(b)
	for _, dist in {8, 14, 24, 40, 70} do
		for k = 0, 7 do
			local a = k * math.pi / 4
			local eye = Vector3.new(c.X + math.cos(a) * dist, groundOf(b) + 4.5, c.Z + math.sin(a) * dist)
			local cam = CFrame.lookAt(eye, c)
			for _, screen in SCREENS do
				local drawn = pipeline(cam, screen.size, pool)
				footprintViews += 1
				for i = 1, #drawn do
					for j = i + 1, #drawn do
						if View.overlaps(drawn[i].rect, drawn[j].rect) then ok(false, "drawn signs overlap on screen") end
					end
				end
				checks += 1
			end
		end
	end
	-- Cluster pairs: the player in front of the pair (both sides) at 12 studs.
	for _, o in near(b, 18) do
		if o ~= b and tostring(o.model:GetFullName()) > tostring(b.model:GetFullName()) then
			clusterPairs += 1
			local ca, cb = centre(b), centre(o)
			local mid = (ca + cb) / 2
			local along = Vector3.new(cb.X - ca.X, 0, cb.Z - ca.Z)
			local normal = if along.Magnitude > .5 then Vector3.new(-along.Z, 0, along.X).Unit else Vector3.new(0, 0, 1)
			for _, side in {1, -1} do
				local eye = Vector3.new(mid.X, math.min(groundOf(b), groundOf(o)) + 4.5, mid.Z) + normal * side * 12
				local cam = CFrame.lookAt(eye, mid)
				for _, screen in SCREENS do
					local _, chosen = pipeline(cam, screen.size, pool)
					local seen = {}
					for _, e in chosen do if e.clear then seen[e.b] = true end end
					if not (seen[b] and seen[o]) then
						table.insert(crowded, string.format("%s / %s (%s, %.1f studs apart)", b.model:GetFullName(), o.model:GetFullName(), screen.name, (cb - ca).Magnitude))
					end
					checks += 1
				end
			end
		end
	end
end
ok(footprintViews > 5000, "footprint views projected (" .. footprintViews .. ")")
ok(clusterPairs >= 10, "cluster pairs checked (" .. clusterPairs .. ")")
if #crowded > 0 then print(table.concat(crowded, "\n")) end
ok(#crowded == 0, "clustered signs read side by side: " .. #crowded .. " pairs crowded")
-- Named clusters from QC H1 are among the checked pairs.
local function centreOf(title, parentName)
	for _, b in boards do
		if b.model:GetAttribute("SignTitle") == title and (not parentName or b.model.Parent.Name == parentName) then return centre(b) end
	end
	return nil
end
do
	local skyway = {}
	for _, t in {"Windpine Grove", "Gloomhollow Caverns", "Tidewater Shoals", "Tempest Spire"} do table.insert(skyway, centreOf(t, "Guild Terrace")) end
	ok(#skyway == 4, "Skyway row signs found")
	for i = 1, 3 do ok((skyway[i + 1] - skyway[i]).Magnitude <= 18, "Skyway row neighbours are a checked cluster") end
	ok(centreOf("Quay Bank") and centreOf("Trade Counter") and centreOf("Market Row"), "hall banners and hall signs found")
end

------------------------------------------------------------------------------
-- QC M4: wall clipping. A billboard is a camera-facing quad at its centre's
-- depth: where that quad passes inside a wall, the wall cuts it. From 8
-- headings at 10 and 18 studs (both screens), where the sign's centre is in
-- clear view, no nearby wall / roof / awning box may intrude.
------------------------------------------------------------------------------
local WALLISH = {"wall", "lintel", "roof", "awning", "canvas", "facade", "gable", "eave", "door", "window", "stall"}
local function wallish(p)
	if not p:IsA("BasePart") or p.Transparency >= .9 then return false end
	local n = p.Name:lower()
	for _, w in WALLISH do if n:find(w, 1, true) then return true end end
	return false
end
local walls = {}
for _, p in world:GetDescendants() do if wallish(p) then table.insert(walls, p) end end
ok(#walls > 50, "wall boxes to test against (" .. #walls .. ")")
-- Ray (origin, dir) against an oriented box: entry distance or nil.
local function hit(box, origin, dir)
	local o = box.CFrame:PointToObjectSpace(origin)
	local r = box.CFrame:VectorToObjectSpace(dir)
	local half = box.Size / 2
	local tmin, tmax = -math.huge, math.huge
	for _, axis in {"X", "Y", "Z"} do
		local oa, ra, h = o[axis], r[axis], half[axis]
		if math.abs(ra) < 1e-9 then
			if oa < -h or oa > h then return nil end
		else
			local t1, t2 = (-h - oa) / ra, (h - oa) / ra
			if t1 > t2 then t1, t2 = t2, t1 end
			tmin, tmax = math.max(tmin, t1), math.min(tmax, t2)
			if tmin > tmax then return nil end
		end
	end
	if tmax < 0 then return nil end
	return math.max(tmin, 0)
end
local function insideBox(box, point)
	local o = box.CFrame:PointToObjectSpace(point)
	local h = box.Size / 2
	return math.abs(o.X) <= h.X and math.abs(o.Y) <= h.Y and math.abs(o.Z) <= h.Z
end
local clipped, clipViews = {}, 0
for _, b in boards do
	local c = centre(b)
	local nearWalls = {}
	for _, w in walls do
		local p = w.CFrame.Position
		local reach = w.Size.Magnitude / 2 + 14
		if (Vector3.new(p.X - c.X, 0, p.Z - c.Z)).Magnitude <= reach and math.abs(p.Y - c.Y) <= w.Size.Magnitude / 2 + 10 then table.insert(nearWalls, w) end
	end
	if #nearWalls > 0 then
		for _, dist in {10, 18} do
			for k = 0, 7 do
				local a = k * math.pi / 4
				local eye = Vector3.new(c.X + math.cos(a) * dist, groundOf(b) + 4.5, c.Z + math.sin(a) * dist)
				local cam = CFrame.lookAt(eye, c)
				local blocked = false
				local toCentre = c - eye
				for _, w in nearWalls do
					if insideBox(w, eye) then blocked = true break end
					local t = hit(w, eye, toCentre)
					if t and t < 1 then blocked = true break end
				end
				if not blocked then
					for _, screen in SCREENS do
						clipViews += 1
						local phone = View.isPhone(screen.size)
						local s = View.scaleFor(toCentre.Magnitude, phone, b.kind)
						local compactForm = View.compact(s)
						local box = b.gui:GetAttribute(if compactForm then "SignCompact" else "SignFull")
						local x, y, depth = View.project(cam, FOV, screen.size, c)
						local rect = View.rect(x, y, box.X, box.Y, if compactForm then b.gui:GetAttribute("SignCompactY") else 0, s)
						local f = (screen.size.Y / 2) / math.tan(math.rad(FOV) / 2)
						local bad = nil
						for gx = 0, 4 do
							for gy = 0, 4 do
								local px = rect.x0 + (rect.x1 - rect.x0) * (.1 + .2 * gx)
								local py = rect.y0 + (rect.y1 - rect.y0) * (.1 + .2 * gy)
								local local3 = Vector3.new((px - screen.size.X / 2) / f, -(py - screen.size.Y / 2) / f, -1)
								local dir = cam:VectorToWorldSpace(local3)
								-- The quad point at this pixel (the sign's depth) inside a wall: cut.
								local onQuad = eye + dir * depth
								for _, w in nearWalls do
									if insideBox(w, onQuad) then bad = w break end
								end
								if bad then break end
							end
							if bad then break end
						end
						if bad then
							table.insert(clipped, string.format("%s cut by %s (%s, %d studs, heading %d)", b.model:GetFullName(), bad:GetFullName(), screen.name, dist, k * 45))
						end
						checks += 1
					end
				end
			end
		end
	end
end
ok(clipViews > 500, "wall-clip views sampled (" .. clipViews .. ")")
if #clipped > 0 then print(table.concat(clipped, "\n")) end
ok(#clipped == 0, "no wall cuts a sign (" .. #clipped .. " views)")

------------------------------------------------------------------------------
-- Client view rules (shared/SignView.lua).
------------------------------------------------------------------------------
ok(View.CAP.phone < View.CAP.desktop and View.CAP.phone <= 10 and View.CAP.desktop <= 24, "visible sign caps (desktop " .. View.CAP.desktop .. ", phone " .. View.CAP.phone .. ")")
for kind in KINDS do
	for _, phone in {false, true} do
		local band = View.band(kind, phone)
		local last = math.huge
		for d = 0, 200, 1 do
			local s = View.scaleFor(d, phone, kind)
			ok(s <= last + 1e-9 and s >= band.min - 1e-9 and s <= band.max + 1e-9, kind .. " scale shrinks with distance and stays in its band at " .. d)
			ok(math.abs(s / View.STEP - math.floor(s / View.STEP + .5)) < 1e-6, kind .. " scale quantised to " .. View.STEP)
			last = s
		end
		if phone then ok(band.min >= .45 - 1e-9 and band.max <= .55 + 1e-9, kind .. " phone band within 0.45-0.55") end
	end
end
ok(View.scaleFor(30, false, "hanging") == View.quantise(22 / 30), "world-space feel: REF / distance between the clamps")
ok(View.compact(View.scaleFor(5, true, "hanging")) and not View.compact(View.scaleFor(5, false, "hanging")), "phones are always compact; desktop is full up close")
ok(View.compact(.65) and not View.compact(.7), "compact under DETAIL (0.7)")
ok(View.quantise(.62) == .6 and View.quantise(.63) == .65, "quantise to 0.05 steps")
ok(View.isPhone(roblox.Vector2.new(844, 390)) and not View.isPhone(roblox.Vector2.new(1366, 768)) and not View.isPhone(roblox.Vector2.new(1024, 768)) and not View.isPhone(nil),
	"phone = viewport under 500 px tall")
ok(View.fadeFor(10, 120) == 0 and View.fadeFor(120, 120) == 1 and View.fadeFor(108, 120) > 0 and View.fadeFor(108, 120) < 1, "fades over the last 20% of MaxDistance")
ok(View.fadeFor(107, 120) == View.quantise(View.fadeFor(107, 120)), "fade quantised")
local entries = {}
for i = 1, 40 do table.insert(entries, {d = i * 3, max = 120}) end
table.insert(entries, {d = 130, max = 120})
local chosen = View.select(entries, View.CAP.phone)
ok(#chosen == View.CAP.phone and chosen[1].d == 3 and chosen[#chosen].d == View.CAP.phone * 3, "nearest N signs are shown")
ok(#View.select({{d = 130, max = 120}}, 8) == 0, "signs beyond MaxDistance are never selected")
ok(#View.select({{d = 0 / 0, max = 120}, {d = 5, max = 120}}, 8) == 1, "a NaN distance is never selected")
do
	local list = {{rect = View.rect(100, 100, 200, 60, 0, 1)}, {rect = View.rect(150, 110, 200, 60, 0, 1)}, {rect = View.rect(400, 100, 100, 60, 0, 1)}, {rect = nil}}
	View.declutter(list)
	ok(list[1].clear and not list[2].clear and list[3].clear and not list[4].clear, "declutter: the nearer sign wins, off-screen signs never draw")
	local r = View.rect(100, 100, 200, 60, 20, .5)
	ok(r.x0 == 50 and r.x1 == 150 and r.y0 == 95 and r.y1 == 125, "screen box scales about the centre with its offset")
	local x, y, depth = View.project(CFrame.lookAt(Vector3.new(0, 0, 0), Vector3.new(0, 0, -10)), 70, roblox.Vector2.new(800, 400), Vector3.new(0, 0, -10))
	ok(x == 400 and y == 200 and math.abs(depth - 10) < 1e-6, "projection: straight ahead is the screen centre")
end
ok(View.bob(1.3, 0, true) == 0 and math.abs(View.bob(1.3, 0, false)) <= View.BOB.amplitude, "bob is small and off with reduced motion")
local cam0 = CFrame.lookAt(Vector3.new(0, 5, 0), Vector3.new(0, 5, -10))
local function nearAngle(a, b) return math.abs(((a - b + 180) % 360) - 180) < 1 end
ok(nearAngle(View.arrowRotation(Vector3.new(0, 0, -1), cam0), -90), "ahead points up the screen")
ok(nearAngle(View.arrowRotation(Vector3.new(1, 0, 0), cam0), 0), "right points right")
ok(nearAngle(View.arrowRotation(Vector3.new(-1, 0, 0), cam0), 180), "left points left")
ok(nearAngle(View.arrowRotation(Vector3.new(0, 0, 1), cam0), 90), "behind points down")
ok(View.glowTransparency(0, .7, .35) == .35 and View.glowTransparency(1, .7, .35) == .7, "crystal glow follows the day factor")
local client = fs.readFile("signs.client.lua")
local code = client:gsub("%-%-[^\n]*", "")
ok(client:sub(1, 9) == "--!strict" and fs.readFile("shared/SignView.lua"):sub(1, 9) == "--!strict", "QC L7: both sign files are --!strict")
ok(not code:find('"Lighting"', 1, true) and not code:find("Instance.new", 1, true), "client never touches Lighting and creates no instances")
ok(source:find("holder.ModelStreamingMode=Enum.ModelStreamingMode.Atomic", 1, true), "QC L3: sign holders stream atomically")
ok(code:find("DescendantAdded", 1, true) and code:find("DescendantRemoving", 1, true), "QC L3: the client follows stream-in and stream-out")
ok(code:find("rec.scaleValue ~= scale", 1, true) and code:find("rec.fade ~= fade", 1, true), "QC M5: scale and fade written only on change")

------------------------------------------------------------------------------
-- The client script, run against mocks of the engine (QC: tag add / remove,
-- enable switch, cap swap on a viewport change, stream-in, bad record
-- recovery, reduced motion).
------------------------------------------------------------------------------
do
	local heartbeat, added, removed = signal(), signal(), signal()
	local camChanged, viewportChanged = signal(), signal()
	local reducedMotion = false
	local poison = nil -- a world position whose projection throws
	local camera = {CFrame = CFrame.new(), ViewportSize = roblox.Vector2.new(1920, 1080)}
	function camera:WorldToViewportPoint(p)
		if poison and (p - poison).Magnitude < 12 then error("projection failed") end
		local x, y, depth = View.project(self.CFrame, FOV, self.ViewportSize, p)
		return Vector3.new(x, y, depth), depth > 0
	end
	function camera:GetPropertyChangedSignal(name) assert(name == "ViewportSize"); return viewportChanged end
	local ws = {CurrentCamera = camera}
	function ws:GetPropertyChangedSignal(name) assert(name == "CurrentCamera"); return camChanged end
	function ws:GetServerTimeNow() return 0 end
	local tagged = {}
	for _, b in boards do
		table.insert(tagged, b.model)
		b.anchor.Position = b.anchor.CFrame.Position -- Lune keeps Position apart from CFrame
	end
	local markers = {AetherSignView = {}, AetherLighting = {}, AetherData = {}, AetherUiTheme = {}}
	local modules = {
		[markers.AetherSignView] = View,
		[markers.AetherLighting] = {dayFactor = function() return 1 end, clockAt = function() return 0 end},
		[markers.AetherData] = {Calendar = {}},
		[markers.AetherUiTheme] = {reducedMotion = function() return reducedMotion end},
	}
	local services = {
		Players = {LocalPlayer = {}},
		RunService = {Heartbeat = heartbeat},
		CollectionService = {
			GetTagged = function() return tagged end,
			GetInstanceAddedSignal = function() return added end,
			GetInstanceRemovedSignal = function() return removed end,
		},
		ReplicatedStorage = {WaitForChild = function(_, n) return markers[n] end},
	}
	luau.load(fs.readFile("signs.client.lua"), {debugName = "signs.client.lua", environment = {
		game = {GetService = function(_, n) return services[n] end},
		workspace = ws, require = function(m) return modules[m] end,
		Vector3 = Vector3, Vector2 = roblox.Vector2, CFrame = CFrame,
		task = {defer = function(f, ...) f(...) end},
	}, injectGlobals = true})()
	local function step() heartbeat:Fire(View.TICK + .001) end
	local function scaleOf(b) return b.gui:FindFirstChild("Sign"):FindFirstChild("Scale").Scale end
	local function enabled()
		local out = {}
		for _, b in boards do if b.gui.Enabled then table.insert(out, b) end end
		return out
	end
	local function look(b, dist)
		local c = centre(b)
		camera.CFrame = CFrame.lookAt(Vector3.new(c.X, groundOf(b) + 4.5, c.Z + dist), c)
	end
	local quay = nil
	for _, b in boards do if b.model:GetAttribute("SignTitle") == "Market Row" then quay = b end end
	look(quay, 10)
	ok(#enabled() == 0, "client: billboards start disabled")
	step()
	local on = enabled()
	ok(#on >= 1 and #on <= View.CAP.desktop, "client: nearby signs enabled, capped (" .. #on .. ")")
	ok(quay.gui.Enabled, "client: the sign in front of the camera is drawn")
	local s = scaleOf(quay)
	ok(math.abs(s / View.STEP - math.floor(s / View.STEP + .5)) < 1e-4 and math.abs(s - View.scaleFor((quay.anchor.Position - camera.CFrame.Position).Magnitude, false, quay.kind)) < 1e-4,
		"client: UIScale is the quantised band scale (" .. s .. ")")
	local rects = {}
	for _, b in on do
		-- Rest height (the client declutters at rest; the bob offset moves with the clock).
		local lift = tonumber(b.gui:GetAttribute("SignLift")) or b.gui.StudsOffsetWorldSpace.Y
		local x, y, depth = View.project(camera.CFrame, FOV, camera.ViewportSize, b.anchor.CFrame.Position + Vector3.new(0, lift, 0))
		local sc = scaleOf(b)
		local box = b.gui:GetAttribute(if View.compact(sc) then "SignCompact" else "SignFull")
		if depth > 0 then table.insert(rects, View.rect(x, y, box.X, box.Y, if View.compact(sc) then b.gui:GetAttribute("SignCompactY") else 0, sc)) end
	end
	local clash = false
	for i = 1, #rects do for j = i + 1, #rects do if View.overlaps(rects[i], rects[j]) then clash = true end end end
	ok(not clash, "client: drawn signs never overlap on screen")
	-- Compact form at distance: the detail layer hides.
	look(quay, 60)
	step()
	if quay.gui.Enabled then
		local detail = quay.gui:FindFirstChild("Sign"):FindFirstChild("Detail")
		ok(not detail or detail.Visible == false, "client: compact form hides the kicker ribbon")
	end
	look(quay, 10)
	step()
	local detail = quay.gui:FindFirstChild("Sign"):FindFirstChild("Detail")
	ok(not detail or detail.Visible == true, "client: full form shows the kicker ribbon up close")
	-- Cap swap: a phone-sized viewport (rotation / resize) switches caps and bands.
	camera.ViewportSize = roblox.Vector2.new(844, 390)
	viewportChanged:Fire()
	step()
	ok(#enabled() <= View.CAP.phone, "client: phone cap after the viewport change (" .. #enabled() .. ")")
	ok(scaleOf(quay) <= View.band(quay.kind, true).max + 1e-4, "client: phone band (UIScale stores float32) after the viewport change")
	camera.ViewportSize = roblox.Vector2.new(1920, 1080)
	viewportChanged:Fire()
	step()
	ok(scaleOf(quay) > View.band(quay.kind, true).max, "client: desktop band restored")
	-- Enable switch: far from every sign, all are off.
	camera.CFrame = CFrame.new(0, 5000, 0)
	step()
	ok(#enabled() == 0, "client: every sign switched off out of range")
	-- Tag removed: the sign is never drawn again.
	look(quay, 10)
	removed:Fire(quay.model)
	quay.gui.Enabled = false
	step()
	ok(not quay.gui.Enabled, "client: a sign whose tag is removed is dropped")
	-- Tag added again (and stream-in: a billboard arriving after its tag).
	added:Fire(quay.model)
	step()
	ok(quay.gui.Enabled, "client: a re-tagged sign is drawn again")
	removed:Fire(quay.model)
	local gui = quay.gui
	gui.Parent = nil
	added:Fire(quay.model)
	step()
	ok(not gui.Enabled, "client: a tagged model without its billboard draws nothing yet")
	gui.Parent = quay.anchor
	instanceSignal(quay.model, "DescendantAdded"):Fire(gui)
	step()
	ok(gui.Enabled, "client: the billboard streaming in later is picked up")
	instanceSignal(quay.model, "DescendantRemoving"):Fire(gui)
	gui.Enabled = false
	step()
	ok(not gui.Enabled, "client: a billboard streaming out is dropped")
	instanceSignal(quay.model, "DescendantAdded"):Fire(gui)
	step()
	-- Bad record: one sign whose projection throws is dropped; the rest keep working.
	poison = centre(quay)
	local others = 0
	step()
	for _, b in enabled() do if b ~= quay then others += 1 end end
	ok(others >= 1, "client: other signs keep drawing after a bad record")
	poison = nil
	quay.gui.Enabled = false
	step()
	ok(not quay.gui.Enabled, "client: the bad record was dropped")
	-- Arrow guard (QC L4): a non-Vector3 SignArrowTo is ignored, not fatal.
	local post = nil
	for _, b in boards do if b.kind == "post" and b.model.Parent.Name == "Compass Quay" then post = b end end
	local arrow = post.gui:FindFirstChild("Arrow", true)
	look(post, 10)
	step()
	ok(post.gui.Enabled, "client: a post is drawn")
	arrow:SetAttribute("SignArrowTo", "nowhere")
	step()
	ok(post.gui.Enabled, "client: a corrupt arrow target is skipped")
	-- Reduced motion: no bob, signs rest at their lift.
	reducedMotion = true
	step()
	heartbeat:Fire(.016)
	ok(math.abs(post.gui.StudsOffsetWorldSpace.Y - post.gui:GetAttribute("SignLift")) < 1e-4, "client: reduced motion keeps signs still")
	reducedMotion = false
	step()
	for _ = 1, 20 do heartbeat:Fire(.05) end
	ok(math.abs(post.gui.StudsOffsetWorldSpace.Y - post.gui:GetAttribute("SignLift")) <= View.BOB.amplitude + 1e-4, "client: bob stays within its amplitude")
end

------------------------------------------------------------------------------
-- QC L6: a torn-down home leaves no ghost behind in the stacking list: the
-- rebuilt home's signs float at their own lift.
------------------------------------------------------------------------------
do
	local function homeSigns()
		local out = {}
		for _, m in collectSigns() do
			if m:FindFirstAncestor("WayfarersRest_77") then out[m:GetAttribute("SignTitle")] = m:FindFirstChildWhichIsA("BasePart"):FindFirstChild("SignBillboard"):GetAttribute("SignLift") end
		end
		return out
	end
	local before = homeSigns()
	ok(next(before) ~= nil, "home signs exist")
	for _, m in collectSigns() do
		if m:FindFirstAncestor("WayfarersRest_77") then instanceSignal(m, "Destroying"):Fire() end
	end
	players.PlayerRemoving:Fire(guest)
	local again = player(77, {HomeGarden = true, HomeDeck = true, Worker1Tier = 1})
	pcall(function() again:SetAttribute("GardenUnlocked", true) end)
	local after = homeSigns()
	for title, lift in before do ok(after[title] == lift, title .. " rebuilt at its own lift (" .. tostring(after[title]) .. ")") end
end

------------------------------------------------------------------------------
-- Source and catalog: the physical kit is gone.
------------------------------------------------------------------------------
local _, guiNew = source:gsub('Instance%.new%("SurfaceGui"%)', "")
ok(guiNew == 1, "world.server.lua creates SurfaceGuis only for ledger boards (" .. guiNew .. ")")
ok(source:find("return (Signs.build(parent,cf,spec))", 1, true), "legacy signAt forwards to Signs.build")
for _, gone in {"SignHangingFrame", "SignpostFrame", "BannerStandardFrame", "SignPlinthFrame", "SignLedgerFrame", "SignCarvedBoard",
	"SignScrollBoard", "SignArrowBoard", "SignPlaqueBoard", "BannerCloth"} do
	ok(World.shapes[gone] == nil and not source:find('"' .. gone .. '"', 1, true), gone .. " scrapped")
end
ok(World.shapes.SignNoticeBoard ~= nil, "the ledger notice board mesh stays")

print(string.format("SIGN-BILLBOARDS: %d billboards, %d GUI instances (%d text labels), caps desktop %d / phone %d", billboards, guiInstances, labelCount, View.CAP.desktop, View.CAP.phone))
ok(guiInstances <= 6500 and labelCount <= 700, "sign GUI instances bounded")
local list = {}
for kind, n in kinds do table.insert(list, kind .. " " .. n) end
table.sort(list)
print("Signs v2: " .. #signs .. " signs (" .. staticSigns .. " static), " .. signParts .. " static sign parts of " .. staticParts .. "; by archetype (incl. home): " .. table.concat(list, ", ") .. ".")
print(string.format("Footprint: %d projected views, %d cluster pairs; wall clip: %d views; smallest rendered text %.1f px.", footprintViews, clusterPairs, clipViews, minRendered))
print("Sign QA passed " .. checks .. " checks.")
print("SUITE-END verify-signs.luau")
