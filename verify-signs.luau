-- Signs (docs/DEPTH-CONTRACT.md §28): every sign in the generated world goes
-- through the shared Signs system in world.server.lua. Builds the real world
-- (static islands plus a home island with its garden, crew haven and builder's
-- terrace) and checks: one archetype per sign model, its frame host and boards
-- carry the sign kit mesh slots (shapes exist, fit boxes valid, declared boxes
-- sane), part counts per archetype, the static part budget, no lights, text
-- that fits its board at every length used (independent re-measure), night
-- readability (LightInfluence, brightness, contrast, distance), fonts, arrow
-- boards that point at their destinations, and no sign standing on a path or
-- swallowing someone else's prompt.
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

------------------------------------------------------------------------------
-- Every SurfaceGui belongs to a sign built by the shared system.
------------------------------------------------------------------------------
local KINDS = {hanging = true, shop = true, post = true, banner = true, plaque = true, ledger = true}
local FRAMES = {hanging = "SignHangingFrame", shop = "SignHangingFrame", post = "SignpostFrame", banner = "BannerStandardFrame",
	plaque = "SignPlinthFrame", ledger = "SignLedgerFrame"}
local BOARDS = {hanging = "SignCarvedBoard", shop = "SignScrollBoard", banner = "BannerCloth", plaque = "SignPlaqueBoard", ledger = "SignNoticeBoard"}
local FONTS = {["rbxasset://fonts/families/Merriweather.json"] = true, ["rbxasset://fonts/families/BuilderSans.json"] = true,
	["rbxasset://fonts/families/Fondamento.json"] = true}
local guis, labels = 0, 0
for _, gui in world:GetDescendants() do
	if gui:IsA("SurfaceGui") then
		guis += 1
		local holder = gui.Parent and gui.Parent.Parent
		ok(holder and holder:GetAttribute("SignArchetype") ~= nil, gui:GetFullName() .. " belongs to a shared-system sign")
		ok(gui.Parent:GetAttribute("SignBoard") == true, gui:GetFullName() .. " sits on a sign board")
		ok(gui.SizingMode == roblox.Enum.SurfaceGuiSizingMode.PixelsPerStud and gui.PixelsPerStud >= 40 and gui.PixelsPerStud <= 80,
			gui:GetFullName() .. " is distance-scaled by PixelsPerStud")
		ok(gui.LightInfluence <= .35 and gui.Brightness >= 1, gui:GetFullName() .. " self-lights for night reading")
		ok(gui.MaxDistance >= 80 and not gui.AlwaysOnTop, gui:GetFullName() .. " reads from afar but never through walls")
		ok(gui:GetAttribute("SignStyled") == true, gui:GetFullName() .. " is styled on the server (the client keeps it)")
		-- §28 performance: PPS 40 (ledgers 600 px across), MaxDistance 100 (landmark plaques 150, ledgers 90).
		local archetype = holder:GetAttribute("SignArchetype")
		if archetype == "ledger" then
			ok(gui.MaxDistance == 90 and math.abs(gui.PixelsPerStud * gui.Parent.Size.X - 600) < 1, gui:GetFullName() .. " ledger face")
		else
			ok(gui.PixelsPerStud == 40, gui:GetFullName() .. " paints at 40 pixels per stud")
			ok(gui.MaxDistance == (if archetype == "plaque" then 150 else 100), gui:GetFullName() .. " MaxDistance by archetype (" .. gui.MaxDistance .. ")")
		end
		-- One outline per label: a UIStroke or an engraved highlight label, never both.
		for _, label in gui:GetChildren() do
			if label:IsA("TextLabel") and not label.Name:find("Shadow", 1, true) and label.Name ~= "Emblem initial" then
				local stroke = label:FindFirstChildOfClass("UIStroke") ~= nil
				local shadow = gui:FindFirstChild(label.Name .. "Shadow") ~= nil
				ok(stroke ~= shadow or (archetype == "ledger" and stroke), label:GetFullName() .. " has exactly one outline (stroke " .. tostring(stroke) .. ", shadow " .. tostring(shadow) .. ")")
			end
		end
		local panel = gui:FindFirstChild("Panel")
		ok(panel ~= nil, gui:GetFullName() .. " has a painted panel")
		local face = gui.Parent.Size
		local cw, ch = face.X * gui.PixelsPerStud, face.Y * gui.PixelsPerStud
		for _, label in gui:GetDescendants() do
			if label:IsA("TextLabel") and not label.Name:find("Shadow", 1, true) and label.Text ~= "" then
				labels += 1
				local w, h, size = label.Size.X.Offset, label.Size.Y.Offset, label.TextSize
				ok(not label.TextScaled and label.TextWrapped, label:GetFullName() .. " uses a fitted text size")
				ok(label:GetAttribute("SignOverflow") == nil, label:GetFullName() .. " text fits without overflow")
				ok(FONTS[label.FontFace.Family] == true, label:GetFullName() .. " uses a sign font face (" .. label.FontFace.Family .. ")")
				local maxLines = label:GetAttribute("SignFitLines") or 1
				if label.Name ~= "Emblem initial" then
					local n = lines(label.Text, size, w)
					ok(n <= maxLines and n * size * 1.25 <= h + 1, label:GetFullName() .. " '" .. label.Text .. "' fits its box (" .. n .. " lines at " .. size .. "px)")
					ok(label.Position.X.Offset >= 0 and label.Position.Y.Offset >= 0 and label.Position.X.Offset + w <= cw + 1 and label.Position.Y.Offset + h <= ch + 1,
						label:GetFullName() .. " stays on its board")
				end
				if label.Name == "Label" and gui.Parent:GetAttribute("Shape") == "SignArrowBoard" then
					-- L6: the label stays >= .45 studs (and past the stretched strap) clear of the tail.
					local W = gui.Parent.Size.X
					local need = math.max(.45, W * .37 / 4.6) * gui.PixelsPerStud
					local tailGap = if gui.Face == roblox.Enum.NormalId.Front then cw - (label.Position.X.Offset + w) else label.Position.X.Offset
					ok(tailGap >= need - 1, label:GetFullName() .. " clears the arrow strap (" .. tailGap .. " px >= " .. math.floor(need) .. ")")
				end
				local studs = size / gui.PixelsPerStud
				if label.Name == "Title" or label.Name == "Label" then
					ok(studs >= .22, label:GetFullName() .. " title is legible (" .. string.format("%.2f", studs) .. " studs)")
					ok(contrast(label.TextColor3, panel.BackgroundColor3) >= 4.5, label:GetFullName() .. " title contrast on its panel")
				elseif label.Name == "Kicker" or label.Name:match("^Row_") or label.Name:match("^Value_") then
					ok(studs >= .12, label:GetFullName() .. " small text is legible")
					ok(contrast(label.TextColor3, panel.BackgroundColor3) >= 3, label:GetFullName() .. " small text contrast")
				end
			end
		end
	end
end
ok(guis >= 150 and labels >= 400, "sign faces painted (" .. guis .. " faces, " .. labels .. " labels)")
-- Source: SurfaceGuis are only created by the sign system (surface() and ledger()).
local _, guiNew = source:gsub('Instance%.new%("SurfaceGui"%)', "")
ok(guiNew == 2, "world.server.lua creates SurfaceGuis only inside the sign system (" .. guiNew .. ")")
ok(source:find("local function signAt", 1, true) and source:find("return (Signs.build(parent,cf,spec))", 1, true), "legacy signAt forwards to Signs.build")

------------------------------------------------------------------------------
-- Sign models: archetype, frame host, boards, parts, icons, no lights.
------------------------------------------------------------------------------
local counts, kinds, signs = {}, {}, {}
local PARTS = {hanging = 2, banner = 2, plaque = 2, ledger = 2, shop = 3}
local function box(p)
	local cf, s = p.CFrame, p.Size / 2
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local e = Vector3.new(math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z,
		math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z, math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z)
	return cf.Position - e, cf.Position + e
end
for _, model in world:GetDescendants() do
	local kind = model:IsA("Model") and model:GetAttribute("SignArchetype")
	if kind then
		table.insert(signs, model)
		ok(KINDS[kind], model:GetFullName() .. " archetype " .. tostring(kind))
		ok(model.Name == "Sign " .. model:GetAttribute("SignTitle"), model:GetFullName() .. " keeps the Sign <title> name")
		kinds[kind] = (kinds[kind] or 0) + 1
		local frames, boards, icons, parts, arrows = {}, {}, 0, 0, 0
		for _, p in model:GetDescendants() do
			ok(not p:IsA("Light"), model:GetFullName() .. " adds no lights")
			if p:IsA("BasePart") then
				parts += 1
				ok(not p.CanCollide, p:GetFullName() .. " never blocks a path")
				local shape = p:GetAttribute("Shape")
				ok(type(shape) == "string", p:GetFullName() .. " is a mesh slot")
				if p:GetAttribute("ShapeBox") then
					table.insert(frames, p)
				elseif p:GetAttribute("SignBoard") then
					table.insert(boards, p)
					if shape == "SignArrowBoard" then arrows += 1 end
				else
					icons += 1
					ok(p:GetAttribute("ShapeFit") == "Uniform" and (Props.shapes[shape] or World.shapes[shape]) ~= nil, p:GetFullName() .. " icon " .. shape .. " is a catalog shape")
				end
			end
		end
		ok(#frames == 1, model:GetFullName() .. " has one frame host")
		local frame = frames[1]
		ok(frame:GetAttribute("Shape") == FRAMES[kind], model:GetFullName() .. " frame shape " .. tostring(frame:GetAttribute("Shape")))
		ok(frame.Transparency < 1, model:GetFullName() .. " frame host stays a visible fallback")
		-- The declared box contains the host and keeps the authored proportions within reason.
		local data = World.shapes[frame:GetAttribute("Shape")]
		ok(data ~= nil and data.kind == "signframe" and data.fit ~= nil, frame:GetAttribute("Shape") .. " is an authored sign frame")
		local declared, offset = frame:GetAttribute("ShapeBox"), frame:GetAttribute("ShapeBoxOffset") or Vector3.zero
		local fitSize = Vector3.new(data.fit[2][1] - data.fit[1][1], data.fit[2][2] - data.fit[1][2], data.fit[2][3] - data.fit[1][3])
		for _, axis in {"X", "Y", "Z"} do
			local k = declared[axis] / fitSize[axis]
			ok(k > .55 and k < 1.6, model:GetFullName() .. " frame stretch " .. axis .. " " .. string.format("%.2f", k))
			ok(math.abs(offset[axis]) + frame.Size[axis] / 2 <= declared[axis] / 2 + .05, model:GetFullName() .. " frame box holds its host on " .. axis)
		end
		ok(frame.CFrame.UpVector.Y > .99, model:GetFullName() .. " frame stands upright")
		ok(#boards >= 1, model:GetFullName() .. " has a text board")
		for _, b in boards do
			local shape = b:GetAttribute("Shape")
			ok(World.shapes[shape] and World.shapes[shape].kind == "sign" and World.shapes[shape].fit ~= nil, b:GetFullName() .. " board mesh " .. shape)
			ok(BOARDS[kind] == nil or shape == BOARDS[kind] or (kind == "post"), b:GetFullName() .. " uses the " .. kind .. " board")
			ok(b:FindFirstChildOfClass("SurfaceGui") ~= nil, b:GetFullName() .. " is painted")
			if shape == "SignArrowBoard" then
				local to = b:GetAttribute("SignArrowTo")
				local base = frame.CFrame.Position
				local flat = Vector3.new(to.X - base.X, 0, to.Z - base.Z)
				ok(flat.Magnitude < .1 or b.CFrame.RightVector:Dot(flat.Unit) > .99, b:GetFullName() .. " points at its destination")
				local rel = b.CFrame.Position - base
				ok(Vector3.new(rel.X, 0, rel.Z).Unit:Dot(flat.Unit) > .99, b:GetFullName() .. " reaches out toward its destination")
				ok(b.CFrame.Position.Y - b.Size.Y / 2 > base.Y - frame.Size.Y / 2 + 1, b:GetFullName() .. " hangs above the ground")
			end
		end
		if kind == "post" then
			ok(arrows >= 1 and parts == 1 + #boards and parts <= 5, model:GetFullName() .. " signpost has 1-4 boards (" .. parts .. " parts)")
		else
			ok(parts == PARTS[kind], model:GetFullName() .. " " .. kind .. " part count " .. parts)
		end
		ok((kind == "shop") == (icons == 1), model:GetFullName() .. " icon only on shop signs")
		counts[kind] = (counts[kind] or 0) + parts
	end
end
ok(#tags.AetherSign == #signs, "every sign is tagged AetherSign")
for kind in KINDS do ok((kinds[kind] or 0) >= 1, kind .. " archetype is used in the world") end
ok(#signs >= 80, "signs across the world (" .. #signs .. ")")
-- Named signs other systems rely on.
for _, name in {"Sign Artificers' Row", "Sign Compass Quay", "Sign Sky Harbor", "Sign Verdant Garden", "Sign Hall of Mastery", "Sign Bestiary"} do
	ok(world:FindFirstChild(name, true) ~= nil, name .. " exists")
end
ok(world:FindFirstChild("Skill Leaderboard", true):FindFirstChild("Row_" .. Data.SkillOrder[1], true) ~= nil, "ledger rows keep their Row_ names")
-- Faction standards keep their prompt (IsleItem/IsleRegion) on the cloth.
local standards = 0
for _, m in world:GetDescendants() do
	if m:IsA("Model") and m:GetAttribute("Faction") then
		local q = m:FindFirstChildWhichIsA("ProximityPrompt", true)
		ok(q and q:GetAttribute("IsleAction") == "factionBoard" and q:GetAttribute("IsleRegion") ~= nil and q.Parent:GetAttribute("Shape") == "BannerCloth",
			m.Name .. " standard is a banner sign with its prompt")
		standards += 1
	end
end
ok(standards == #Data.Factions.Order, "every faction has a banner standard")

------------------------------------------------------------------------------
-- One-sided boards (§28 performance): only a board whose back looks into a
-- wall or over the rim loses its Back face; independent re-measure.
------------------------------------------------------------------------------
local function islandOf(node)
	while node.Parent ~= islands and node.Parent ~= archipelago do node = node.Parent end
	return node
end
local function containsPoint(p, pos)
	local rel = p.CFrame:PointToObjectSpace(pos)
	local h = p.Size / 2
	if p:IsA("Part") and p.Shape == roblox.Enum.PartType.Cylinder then
		return math.abs(rel.X) <= h.X and rel.Y ^ 2 + rel.Z ^ 2 <= math.min(h.Y, h.Z) ^ 2
	elseif p:IsA("Part") and p.Shape == roblox.Enum.PartType.Ball then
		return rel.Magnitude <= math.min(h.X, h.Y, h.Z)
	end
	return math.abs(rel.X) <= h.X and math.abs(rel.Y) <= h.Y and math.abs(rel.Z) <= h.Z
end
local function backReason(board)
	local solids = {}
	for _, p in islandOf(board):GetDescendants() do
		if p:IsA("BasePart") and (p.CanCollide or p.Transparency < 1) and not p.Parent:GetAttribute("SignArchetype") then table.insert(solids, p) end
	end
	local back, c = -board.CFrame.LookVector, board.CFrame.Position
	for _, d in {1, 2.5} do
		for _, p in solids do if containsPoint(p, c + back * (board.Size.Z / 2 + d)) then return "wall" end end
	end
	for _, d in {3, 5.5, 8} do
		local probe, ground = c + back * (board.Size.Z / 2 + d), false
		for _, p in solids do
			if p.CanCollide then
				local lo, hi = box(p)
				if hi.Y <= probe.Y + .5 and hi.Y >= probe.Y - 40 and containsPoint(p, Vector3.new(probe.X, (lo.Y + hi.Y) / 2, probe.Z)) then ground = true; break end
			end
		end
		if not ground then return "rim" end
	end
	return nil
end
local oneSided, twoSided = 0, 0
for _, board in world:GetDescendants() do
	if board:IsA("BasePart") and board:GetAttribute("SignBoard") and board.Parent:GetAttribute("SignArchetype") ~= "ledger" then
		local backFace = board:FindFirstChild("Sign face Back")
		if board:GetAttribute("Shape") == "SignArrowBoard" then
			ok(backFace ~= nil, board:GetFullName() .. " arrow keeps both faces")
		elseif board:GetAttribute("SignOneSided") then
			oneSided += 1
			ok(backFace == nil and board:FindFirstChild("Sign face Front") ~= nil, board:GetFullName() .. " one-sided board keeps its Front face only")
			ok(backReason(board) == board:GetAttribute("SignOneSided"), board:GetFullName() .. " back faces " .. tostring(board:GetAttribute("SignOneSided")))
		else
			twoSided += 1
			ok(backFace ~= nil and backReason(board) == nil, board:GetFullName() .. " readable back keeps its Back face")
		end
	end
end
ok(oneSided + twoSided >= 80, "every non-ledger board classified (" .. oneSided .. " one-sided, " .. twoSided .. " two-sided)")
print("One-sided boards: " .. oneSided .. " (back over a wall or the rim); two-sided: " .. twoSided .. ".")
ok(not source:find("Enum.Font.Merriweather", 1, true) and not source:find("pcall(function() l.FontFace", 1, true), "no dead Font fallback (FontFace is always set)")

------------------------------------------------------------------------------
-- Placement: no sign host on a path, no foreign prompt inside a sign.
------------------------------------------------------------------------------
local paths, prompts = {}, {}
for _, obj in world:GetDescendants() do
	if obj:IsA("BasePart") and obj.Name == "Path" then table.insert(paths, obj) end
	if obj:IsA("ProximityPrompt") and obj.Parent:IsA("BasePart") then table.insert(prompts, obj) end
end
ok(#paths > 10 and #prompts > 100, "paths and prompts to check against")
local function overlapXZ(a, b, pad)
	local alo, ahi = box(a)
	local blo, bhi = box(b)
	return alo.X < bhi.X - pad and blo.X < ahi.X - pad and alo.Z < bhi.Z - pad and blo.Z < ahi.Z - pad
end
local function inside(model, obj)
	local node = obj
	while node do if node == model then return true end; node = node.Parent end
	return false
end
for _, model in signs do
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p:GetAttribute("ShapeBox") then
			for _, path in paths do
				-- Only the footing of the host matters (boards hang overhead).
				local lo = box(p)
				local _, phi = box(path)
				if math.abs(lo.Y - phi.Y) < 1.5 then ok(not overlapXZ(p, path, .3), p:GetFullName() .. " stands clear of " .. path:GetFullName()) end
			end
		end
		if p:IsA("BasePart") then
			local lo, hi = box(p)
			for _, q in prompts do
				if not inside(model, q) then
					local host = q.Parent
					local c = host.CFrame.Position
					ok(not (c.X > lo.X and c.X < hi.X and c.Y > lo.Y and c.Y < hi.Y and c.Z > lo.Z and c.Z < hi.Z),
						p:GetFullName() .. " does not swallow the prompt on " .. host:GetFullName())
				end
			end
		end
	end
end

------------------------------------------------------------------------------
-- Mesh kit: shapes, aliases, forge declared-box support and mobile sharing.
------------------------------------------------------------------------------
local forge = fs.readFile("forge.client.lua")
for _, name in {"SignHangingFrame", "SignpostFrame", "BannerStandardFrame", "SignPlinthFrame", "SignLedgerFrame", "SignCarvedBoard",
	"SignScrollBoard", "SignArrowBoard", "SignPlaqueBoard", "BannerCloth", "SignNoticeBoard"} do
	local data = World.shapes[name]
	ok(data ~= nil and #data.faces >= 200 and #data.faces <= 1500, name .. " is authored within the world triangle range")
	ok(data.fit ~= nil and (data.kind == "sign" or data.kind == "signframe"), name .. " declares its fit box and kind")
end
for _, alias in {"OrnateBracket", "ScrollBoard", "Crest", "Finial", "ChainLink", "ArrowBoard"} do
	ok(forge:find(alias .. " = \"", 1, true) ~= nil, "forge alias " .. alias)
end
ok(forge:find('GetAttribute("ShapeBox")', 1, true) and forge:find('GetAttribute("ShapeBoxOffset")', 1, true), "forge honours declared sign frame boxes")
ok(forge:find("if not SIGN_KIT_SHAPES[shapeName] then return tint end", 1, true) ~= nil and forge:find("if mobile then return defaultTint(data) end", 1, true) ~= nil,
	"only the eleven kit shapes share templates on phones (legacy sign shapes keep their Tint; behaviour tested in verify-mesh)")

local guiPixels, guiCount, guiInstances, labelsN = 0, 0, 0, 0
for _, gui in world:GetDescendants() do
	if gui:IsA("SurfaceGui") then
		guiCount += 1
		local face = gui.Parent.Size
		local fx = if gui.Face == roblox.Enum.NormalId.Front or gui.Face == roblox.Enum.NormalId.Back then face.X else face.Z
		guiPixels += math.floor(fx * gui.PixelsPerStud) * math.floor(face.Y * gui.PixelsPerStud)
		for _, d in gui:GetDescendants() do guiInstances += 1; if d:IsA("TextLabel") then labelsN += 1 end end
	end
end
print(string.format("SIGN-FACES: %d SurfaceGuis, %.2f Mpx canvas, %d GUI instances (%d text labels)", guiCount, guiPixels / 1e6, guiInstances, labelsN))
-- §28 performance budget (before the pass: 234 faces, 11.55 Mpx, 4,570 GUI instances, 1,088 labels at PPS 56).
ok(guiPixels <= 6.5e6, "sign canvas stays under 6.5 Mpx (" .. string.format("%.2f", guiPixels / 1e6) .. ")")
ok(guiInstances <= 4400 and labelsN <= 900, "sign GUI instances bounded (" .. guiInstances .. " instances, " .. labelsN .. " labels)")

local parts = {}
for kind, n in counts do table.insert(parts, kind .. " " .. n) end
table.sort(parts)
print("Signs: " .. #signs .. " signs (" .. staticSigns .. " static), " .. signParts .. " static sign parts of " .. staticParts
	.. "; parts by archetype (incl. home): " .. table.concat(parts, ", ") .. "; " .. guis .. " faces, " .. labels .. " labels.")
print("Sign QA passed " .. checks .. " checks.")
print("SUITE-END verify-signs.luau")
