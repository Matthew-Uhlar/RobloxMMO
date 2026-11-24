-- Companions (Pets depth): every nearby player's summoned pet follows them.
-- The server publishes player attribute ActivePet = "speciesId:rarity:level"
-- ("" when dismissed); each client builds the follower locally from
-- Data.PetDepth.bodyPlan (primitives only, <= 15 anchored, non-colliding,
-- non-queryable parts), so nothing replicates per frame. §48: the model is
-- tagged IsleCreature (CreatureRig pet_<form>), and creatures.client.lua
-- replaces those primitives with the forged pet mesh while it can. Flyers and floaters
-- hover and bob, ground pets hop while their owner moves; wings flap.
-- Followers are built within RANGE studs of the camera and released beyond
-- RELEASE_RANGE; between the two an existing follower is kept and a missing
-- one is not built (hysteresis: no release/rebuild thrash at the edge).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data
local ok = pcall(function() Data = require(ReplicatedStorage:WaitForChild("AetherData", 15)) end)
if not ok or type(Data) ~= "table" or type(Data.PetDepth) ~= "table" then return end
local PD = Data.PetDepth

local RANGE = 160
local RELEASE_RANGE = 180
local TICK = 1 / 30
local SIDE = Vector3.new(-3.2, 0, 1.6) -- left of and slightly behind the owner (the legacy bond companion sits right)
local SHAPES = {Ball = Enum.PartType.Ball, Block = Enum.PartType.Block, Cylinder = Enum.PartType.Cylinder}

local folder = Instance.new("Folder")
folder.Name = "Companions"
folder.Parent = workspace

local followers = {} -- [player] = {key, model, parts, offsets, flaps, plan, pos, yaw, t}
local Companions = {followers = followers, folder = folder, RANGE = RANGE, RELEASE_RANGE = RELEASE_RANGE}

local function color(hex)
	local okColor, value = pcall(Color3.fromHex, hex)
	return okColor and value or Color3.new(0.8, 0.8, 0.8)
end

-- Build one follower model from a body plan.
function Companions.build(speciesId, rarity, ownerName)
	local plan = PD.bodyPlan(speciesId, rarity)
	local model = Instance.new("Model")
	model.Name = ownerName .. "'s " .. ((Data.PetById[speciesId] or {}).name or speciesId)
	local parts, offsets, flaps = {}, {}, {}
	local scale = plan.scale
	for i, spec in ipairs(plan.parts) do
		if i > PD.MAX_PARTS then break end
		local part
		if spec.shape == "Wedge" then
			part = Instance.new("WedgePart")
		else
			part = Instance.new("Part")
			part.Shape = SHAPES[spec.shape] or Enum.PartType.Block
		end
		part.Name = spec.name
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Massless = true
		part.Size = Vector3.new(spec.size[1], spec.size[2], spec.size[3]) * scale
		part.Color = color(spec.color)
		part.Material = if spec.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.Transparency = spec.transparency or 0
		part.Parent = model
		local rot = spec.rot or {0, 0, 0}
		local offset = CFrame.new(spec.offset[1] * scale, spec.offset[2] * scale, spec.offset[3] * scale)
			* CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
		table.insert(parts, part)
		table.insert(offsets, offset)
		flaps[#parts] = spec.flap
	end
	-- §48: creatures.client.lua draws the forged pet rig (pet_<form>) over these
	-- primitives and hides them locally; they stay as the fallback when the
	-- forge has no room. The body (first part) is the rig's root.
	pcall(function()
		model.PrimaryPart = parts[1]
		model:SetAttribute("CreatureRig", "pet_" .. tostring(plan.form))
		model:SetAttribute("CreatureScale", scale)
		model:SetAttribute("Color", (Data.PetById[speciesId] or {}).color or "CCCCCC")
		model:SetAttribute("Pet", true)
		game:GetService("CollectionService"):AddTag(model, "IsleCreature")
	end)
	model.Parent = folder
	return {model = model, parts = parts, offsets = offsets, flaps = flaps, plan = plan, t = math.random() * 6}
end

local function release(player)
	local f = followers[player]
	if f then
		f.model:Destroy()
		followers[player] = nil
	end
end
Companions.release = release

-- Pose every part from the follower's body CFrame (one BulkMoveTo per pet).
local cframes = {}
local function pose(f, body)
	table.clear(cframes)
	local flap = math.sin(f.t * 14) * 0.6
	for i, offset in ipairs(f.offsets) do
		local side = f.flaps[i]
		if side then
			-- Hinge at the wing root (toward the body), so the tip sweeps.
			local s = if side == "L" then 1 else -1
			local hinge = Vector3.new(s * 0.6 * f.plan.scale, 0, 0)
			cframes[i] = body * CFrame.new(offset.Position + hinge) * CFrame.Angles(0, 0, s * flap) * CFrame.new(-hinge)
		else
			cframes[i] = body * offset
		end
	end
	workspace:BulkMoveTo(f.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

function Companions.step(dt)
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position
	for _, player in ipairs(Players:GetPlayers()) do
		local id, rarity = PD.parseAttribute(player:GetAttribute("ActivePet"))
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local dist = root and eye and (root.Position - eye).Magnitude or 0
		local far = dist > (if followers[player] then RELEASE_RANGE else RANGE)
		if not id or not root or far then
			release(player)
		else
			local key = id .. ":" .. rarity
			local f = followers[player]
			if f and f.key ~= key then release(player); f = nil end
			if not f then
				f = Companions.build(id, rarity, player.Name)
				f.key = key
				followers[player] = f
			end
			f.t += dt
			local look = root.CFrame
			local height = if f.plan.floating then 1.6 + math.sin(f.t * 2.4) * 0.35 else -2.2 + 0.55 * f.plan.scale
			local target = (look * CFrame.new(SIDE)).Position + Vector3.new(0, height, 0)
			local moving = root.AssemblyLinearVelocity.Magnitude > 2
			if not f.plan.floating and moving then target += Vector3.new(0, math.abs(math.sin(f.t * 9)) * 0.45, 0) end
			if not f.pos or (f.pos - target).Magnitude > 40 then f.pos = target end
			f.pos = f.pos:Lerp(target, 1 - math.exp(-dt * 7))
			local forward = look.LookVector
			local yaw = math.atan2(-forward.X, -forward.Z)
			pose(f, CFrame.new(f.pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, math.pi, 0))
		end
	end
	for player in pairs(followers) do
		if player.Parent == nil then release(player) end
	end
end

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < TICK then return end
	local step = math.min(elapsed, 0.25)
	elapsed = 0
	Companions.step(step)
end)
Players.PlayerRemoving:Connect(release)
