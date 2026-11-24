-- Skysailing vessel host (ServerScriptService.Skysailing; docs/DEPTH-CONTRACT.md §51).
-- The Adventure script (server.server.lua, Skysailing block) owns every rule:
-- who may launch, crew, cargo, XP, the pose sanity checks and every safety
-- landing. This script only builds, seats, moves back and removes the vessel
-- models, through one synchronous BindableFunction ServerStorage.IsleVesselHost:
--   "spawn"   {id, owner, spec, cf}     -> {ok, reason}  builds the ship at cf (the helm seat is "helm")
--   "despawn" {id}                      -> true          unseats everyone, removes the model
--   "pose"    {id}                      -> {position, look, velocity, seated = {[Player] = role}} | nil
--   "reset"   {id, cf}                  -> true          snaps back to cf; the server owns the hull for RESET_HOLD s
--   "seat"    {id, player, role}        -> true|false    seats the player's humanoid in that seat
--   "unseat"  {id, player}              -> true
--   "state"   {id, text, trim, captain} -> true          VesselState / SailTrim attributes for every client
--   "fire"    {id, gunner, dir}         -> true          VesselFire "<seq>:<dx>:<dz>:<userId>" (muzzle flash on clients)
-- A vessel is one unanchored assembly under Workspace.IsleVessels: the Hull
-- root (forged hull mesh on the client, attribute ShipShape), a walkable deck,
-- mast(s), invisible SailSlot parts (the client hangs local cloth sails on
-- them), the helm wheel, deck cannons and one Seat per crew role, welded to
-- the root. The root carries a LinearVelocity and an AlignOrientation; the
-- captain's client (the network owner) drives them, the server holds the hull
-- still whenever it owns it. No server lights, no Neon: every glow is local.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local SS = Data.Skysailing

local Host = {vessels = {}, RESET_HOLD = 1, fireSeq = 0}
local V3, C3 = Vector3.new, Color3.fromHex
local PLANK, BARK, BRASS, CLOTH = C3("A57C55"), C3("5A4030"), C3("C9A24E"), C3("E9DFC7")

local function folder()
	local f = workspace:FindFirstChild("IsleVessels")
	if not f then
		f = Instance.new("Folder")
		f.Name = "IsleVessels"
		f.Parent = workspace
	end
	return f
end
local function newPart(class, model, name, size, color, material, collide)
	local p = Instance.new(class)
	p.Name, p.Size, p.Color = name, size, color
	p.Material = material or Enum.Material.WoodPlanks
	p.Anchored, p.CanCollide, p.CanTouch = false, collide == true, false
	p.CanQuery = collide == true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end
-- Role seats along the deck: helm aft, sails amidships, cannons on the beams.
function Host.layout(spec)
	local L, B, D = spec.length, spec.beam, spec.deck
	local seats = {{role = "helm", at = V3(0, D + 0.6, L * 0.36)}}
	for i = 1, spec.seats.sails do seats[#seats + 1] = {role = "sails" .. i, at = V3((i == 1 and -1 or 1) * B * 0.22, D + 0.6, L * 0.08)} end
	for i = 1, spec.seats.cannons do
		local side = if i % 2 == 1 then -1 else 1
		local row = math.floor((i - 1) / 2)
		seats[#seats + 1] = {role = "cannon" .. i, at = V3(side * (B * 0.5 - 1.4), D + 0.6, -L * 0.12 + row * L * 0.2), side = side}
	end
	local masts = if spec.class >= 3 then {-L * 0.18, L * 0.12} elseif spec.class == 2 then {-L * 0.05} else {-L * 0.02}
	return seats, masts
end
function Host.build(id, owner, spec, cf)
	local model = Instance.new("Model")
	model.Name = "Vessel_" .. tostring(owner and owner.UserId or id)
	model:SetAttribute("VesselId", id)
	model:SetAttribute("VesselOwner", owner and owner.UserId or 0)
	model:SetAttribute("VesselHull", spec.hull)
	model:SetAttribute("VesselClass", spec.class)
	model:SetAttribute("VesselDeck", spec.deck)
	model:SetAttribute("VesselState", SS.encodeState(spec.hp, spec.hp, 0.5, SS.maxSpeed(spec), 1, "open"))
	local L, B, D = spec.length, spec.beam, spec.deck
	local offsets = {}
	local root = newPart("Part", model, "Hull", V3(B, D, L), BARK, Enum.Material.WoodPlanks, true)
	root:SetAttribute("ShipShape", spec.shape)
	root:SetAttribute("ShipFit", "Stretch")
	offsets[root] = CFrame.new(0, D / 2, 0)
	model.PrimaryPart = root
	local deck = newPart("Part", model, "Deck", V3(B - 0.8, 0.4, L - 2), PLANK, Enum.Material.WoodPlanks, true)
	deck.Transparency = 1 -- the forged hull shows the deck; this is the walkable collider
	offsets[deck] = CFrame.new(0, D + 0.2, 0)
	local seats, masts = Host.layout(spec)
	local mastH = 9 + spec.class * 4
	for i, z in ipairs(masts) do
		local mast = newPart("Part", model, "Mast" .. i, V3(0.7, mastH, 0.7), BARK, Enum.Material.Wood, false)
		mast:SetAttribute("ShipShape", "ShipMast")
		offsets[mast] = CFrame.new(0, D + mastH / 2, z)
		local slot = newPart("Part", model, "SailSlot" .. i, V3(B * 1.15, mastH * 0.62, 0.2), CLOTH, Enum.Material.Fabric, false)
		slot.Transparency = 1 -- local cloth (sailing.client.lua) hangs here
		slot:SetAttribute("SailSlot", i)
		offsets[slot] = CFrame.new(0, D + mastH * 0.55, z - 0.6)
	end
	for _, s in ipairs(seats) do
		local seat = newPart("Seat", model, s.role, V3(1.6, 0.4, 1.6), PLANK, Enum.Material.WoodPlanks, false)
		seat.Transparency = 1
		seat:SetAttribute("SailRole", s.role)
		local face = if s.side then CFrame.Angles(0, -s.side * math.pi / 2, 0) else CFrame.new()
		offsets[seat] = CFrame.new(s.at) * face
		if s.role == "helm" then
			local wheel = newPart("Part", model, "Helm wheel", V3(1.6, 2.2, 0.6), BARK, Enum.Material.Wood, false)
			wheel:SetAttribute("ShipShape", "ShipHelm")
			offsets[wheel] = CFrame.new(s.at + V3(0, 0.9, -1.6))
		elseif string.sub(s.role, 1, 6) == "cannon" then
			local gun = newPart("Part", model, "Cannon " .. s.role, V3(1.2, 1.1, 2.6), BRASS, Enum.Material.Metal, false)
			gun:SetAttribute("ShipShape", "DeckCannon")
			offsets[gun] = CFrame.new(s.at + V3(s.side * 1.2, 0.3, 0)) * CFrame.Angles(0, -s.side * math.pi / 2, 0)
		end
	end
	-- The gangway: crew board here (server rules in the Skysailing block).
	local gangway = newPart("Part", model, "Gangway", V3(2, 0.3, 4), PLANK, Enum.Material.WoodPlanks, false)
	gangway.Transparency = 1
	offsets[gangway] = CFrame.new(B * 0.5 + 0.6, D, 0)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText, prompt.ObjectText = "Board as crew", (spec.name or "Ship")
	prompt.HoldDuration, prompt.MaxActivationDistance, prompt.RequiresLineOfSight = 0.35, 14, false
	prompt:SetAttribute("IsleAction", "sailBoard")
	prompt:SetAttribute("IsleItem", tostring(owner and owner.UserId or 0))
	prompt.Parent = gangway
	-- Drive: the captain's client sets these locally while it owns the assembly.
	local attach = Instance.new("Attachment")
	attach.Name = "Drive"
	attach.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Name = "Drive"
	lv.Attachment0 = attach
	pcall(function() lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector end)
	pcall(function() lv.RelativeTo = Enum.ActuatorRelativeTo.World end)
	lv.MaxForce = math.huge
	lv.VectorVelocity = Vector3.zero
	lv.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Name = "Heading"
	ao.Attachment0 = attach
	pcall(function() ao.Mode = Enum.OrientationAlignmentMode.OneAttachment end)
	ao.MaxTorque, ao.Responsiveness = math.huge, 18
	pcall(function() ao.CFrame = cf - cf.Position end)
	ao.Parent = root
	local record = {id = id, model = model, root = root, owner = owner, offsets = offsets, spec = spec, drive = lv, heading = ao}
	-- Place every part first, then weld (a WeldConstraint keeps the offset it is created with).
	Host.place(record, cf)
	for part in pairs(offsets) do
		if part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = root, part
			weld.Parent = part
		end
	end
	model.Parent = folder()
	Host.own(record, owner)
	return record
end
-- Moves every part to `cf` (the root's pose) without PivotTo (headless-safe).
function Host.place(record, cf)
	local base = cf * record.offsets[record.root]:Inverse() -- the model origin (keel line) under the root
	for part, offset in pairs(record.offsets) do
		part.CFrame = if part == record.root then cf else base * offset
	end
	pcall(function() record.root.AssemblyLinearVelocity = Vector3.zero end)
end
function Host.own(record, player)
	record.owned = player
	pcall(function() record.root:SetNetworkOwner(player) end)
end
local function humanoidOf(player)
	local character = player and player.Character
	return character and character:FindFirstChildOfClass("Humanoid"), character
end
function Host.seatOf(record, role)
	local seat = record.model:FindFirstChild(role)
	return if seat and seat:IsA("Seat") then seat else nil
end
function Host.seated(record)
	local out = {}
	for _, seat in ipairs(record.model:GetChildren()) do
		if seat:IsA("Seat") then
			local occupant = seat.Occupant
			local player = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
			if player then out[player] = seat.Name end
		end
	end
	return out
end
function Host.seat(record, player, role)
	local seat = Host.seatOf(record, role)
	local humanoid, character = humanoidOf(player)
	if not seat or not humanoid or not character then return false end
	if seat.Occupant and seat.Occupant ~= humanoid then return false end
	if seat.Occupant == humanoid then return true end
	pcall(function() character:PivotTo(seat.CFrame * CFrame.new(0, 2.5, 0)) end)
	local ok = pcall(function() seat:Sit(humanoid) end)
	return ok
end
function Host.unseat(record, player)
	local humanoid = humanoidOf(player)
	for _, seat in ipairs(record.model:GetChildren()) do
		if seat:IsA("Seat") and humanoid and seat.Occupant == humanoid then
			local weld = seat:FindFirstChild("SeatWeld")
			if weld then weld:Destroy() end
			pcall(function() humanoid.Sit = false end)
		end
	end
	return true
end
function Host.despawn(record)
	for _, seat in ipairs(record.model:GetChildren()) do
		if seat:IsA("Seat") then
			local weld = seat:FindFirstChild("SeatWeld")
			if weld then weld:Destroy() end
		end
	end
	record.model:Destroy()
	Host.vessels[record.id] = nil
	return true
end

Host.ops = {
	spawn = function(payload)
		if Host.vessels[payload.id] then return {ok = false, reason = "exists"} end
		if type(payload.spec) ~= "table" or typeof(payload.cf) ~= "CFrame" then return {ok = false, reason = "invalid"} end
		local ok, record = pcall(Host.build, payload.id, payload.owner, payload.spec, payload.cf)
		if not ok then warn("[Skysailing] could not build vessel: " .. tostring(record)) return {ok = false, reason = "build"} end
		Host.vessels[payload.id] = record
		return {ok = true}
	end,
	despawn = function(payload)
		local record = Host.vessels[payload.id]
		return if record then Host.despawn(record) else true
	end,
	pose = function(payload)
		local record = Host.vessels[payload.id]
		if not record or not record.model.Parent then return nil end
		local cf = record.root.CFrame
		return {position = cf.Position, look = cf.LookVector, velocity = record.root.AssemblyLinearVelocity, seated = Host.seated(record)}
	end,
	reset = function(payload)
		local record = Host.vessels[payload.id]
		if not record or typeof(payload.cf) ~= "CFrame" then return false end
		Host.own(record, nil)
		Host.place(record, payload.cf)
		local owner = record.owner
		record.resetAt = os.clock()
		task.delay(Host.RESET_HOLD, function()
			if Host.vessels[record.id] == record and os.clock() - record.resetAt >= Host.RESET_HOLD - 0.05 then Host.own(record, owner) end
		end)
		return true
	end,
	seat = function(payload)
		local record = Host.vessels[payload.id]
		return record ~= nil and type(payload.role) == "string" and Host.seat(record, payload.player, payload.role)
	end,
	unseat = function(payload)
		local record = Host.vessels[payload.id]
		return if record then Host.unseat(record, payload.player) else true
	end,
	state = function(payload)
		local record = Host.vessels[payload.id]
		if not record then return false end
		if type(payload.text) == "string" then record.model:SetAttribute("VesselState", payload.text) end
		if type(payload.trim) == "number" then record.model:SetAttribute("SailTrim", payload.trim) end
		return true
	end,
	fire = function(payload)
		local record = Host.vessels[payload.id]
		if not record or typeof(payload.dir) ~= "Vector3" then return false end
		Host.fireSeq += 1
		local gunner = payload.gunner
		record.model:SetAttribute("VesselFire", string.format("%d:%.3f:%.3f:%d", Host.fireSeq, payload.dir.X, payload.dir.Z, gunner and gunner.UserId or 0))
		return true
	end,
}
local existing = ServerStorage:FindFirstChild("IsleVesselHost")
local fn = if existing and existing:IsA("BindableFunction") then existing else Instance.new("BindableFunction")
fn.Name = "IsleVesselHost"
function Host.invoke(op, payload)
	local handler = type(op) == "string" and Host.ops[op]
	if not handler or type(payload) ~= "table" then return nil end
	return handler(payload)
end
pcall(function() fn.OnInvoke = Host.invoke end) -- (headless harnesses cannot assign callbacks)
fn.Parent = ServerStorage
if SailingHostTest then SailingHostTest(Host, fn) end
