-- GestureRelay: re-broadcasts cosmetic gestures. See docs/DEPTH-CONTRACT.md §10.
-- Client → server: IsleGesture:FireServer(name, targetPart?, itemId?)
-- Server → nearby clients: IsleGesture:FireClient(other, sourcePlayer, name, targetPart?, itemId?)
-- Nothing here changes gameplay: the name is whitelisted, the target must be a
-- workspace BasePart near the sender, itemId only tints the held model, and each
-- player gets a small token bucket (4 per second). Bad input is silently dropped.

local Relay = {}
Relay.NAMES = {mine = true, chop = true, fish = true, harvest = true, hammer = true, stir = true, flip = true, saw = true,
	interact = true, attack = true, eat = true, drink = true,
	-- Weapon classes (Data.Held.ATTACK): dagger thrust, greatblade / maul cleave, glaive lunge.
	thrust = true, cleave = true, lunge = true,
	-- Combat styles: bow shot, staff cast, wand flick, Mend.
	shoot = true, cast = true, flick = true, heal = true,
	-- Hunter: set / collect a trap, sweep a net. (Agility moves are not relayed:
	-- every client animates runners from their AgilityMove attribute.)
	settrap = true, netswing = true}
-- Combat gestures tint their held bow / staff / wand by the weapon of that style.
Relay.STYLE_GESTURE = {shoot = "ranged", cast = "magic", flick = "magic"}
Relay.MELEE_GESTURE = {attack = true, thrust = true, cleave = true, lunge = true}
Relay.TARGET_RANGE = 20
Relay.BROADCAST_RANGE = 120
Relay.RATE = 4 -- tokens per second
Relay.BURST = 4
Relay.TOOL_KIND = {mine = "Pickaxe", chop = "Hatchet", fish = "Rod", harvest = "Hoe"}

-- itemId must describe the gesture's held item, or be nil.
function Relay.itemOk(Data, name, itemId)
	if itemId == nil then return true end
	if type(itemId) ~= "string" or #itemId > 64 then return false end
	local def = Data.Items[itemId]
	if not def then return false end
	local kind = Relay.TOOL_KIND[name]
	if kind then return def.kind == "tool" and def.toolKind == kind end
	if Relay.MELEE_GESTURE[name] then return def.kind == "weapon" end
	if Relay.STYLE_GESTURE[name] then return def.kind == "weapon" and def.style == Relay.STYLE_GESTURE[name] end
	if name == "eat" or name == "drink" then return def.kind == "consumable" end
	return false
end

-- deps: now(), Data, rootPosition(player) -> Vector3?, targetPosition(target) -> Vector3? (nil
-- when not a workspace BasePart), players() -> list, send(recipient, source, name, target, itemId)
function Relay.create(deps)
	local R = {buckets = {}}
	function R.allow(player)
		local now = deps.now()
		local b = R.buckets[player]
		if not b then
			b = {tokens = Relay.BURST, stamp = now}
			R.buckets[player] = b
		end
		b.tokens = math.min(Relay.BURST, b.tokens + (now - b.stamp) * Relay.RATE)
		b.stamp = now
		if b.tokens < 1 then return false end
		b.tokens -= 1
		return true
	end
	-- Returns ok, reason-or-recipients.
	function R.handle(player, name, target, itemId)
		if type(name) ~= "string" or #name > 16 or not Relay.NAMES[name] then return false, "name" end
		if not Relay.itemOk(deps.Data, name, itemId) then return false, "item" end
		local origin = deps.rootPosition(player)
		if not origin then return false, "character" end
		if target ~= nil then
			local position = deps.targetPosition(target)
			if not position then return false, "target" end
			if (position - origin).Magnitude > Relay.TARGET_RANGE then return false, "distance" end
		end
		if not R.allow(player) then return false, "rate" end
		local recipients = {}
		for _, other in ipairs(deps.players()) do
			if other ~= player then
				local at = deps.rootPosition(other)
				if at and (at - origin).Magnitude <= Relay.BROADCAST_RANGE then
					table.insert(recipients, other)
					deps.send(other, player, name, target, itemId)
				end
			end
		end
		return true, recipients
	end
	function R.forget(player) R.buckets[player] = nil end
	return R
end

if __GestureRelayHarness then
	__GestureRelayHarness(Relay)
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Data = require(ReplicatedStorage:WaitForChild("AetherData"))

local remote = ReplicatedStorage:FindFirstChild("IsleGesture") or Instance.new("RemoteEvent")
remote.Name = "IsleGesture"
remote.Parent = ReplicatedStorage

local relay = Relay.create({
	now = os.clock, Data = Data, players = function() return Players:GetPlayers() end,
	rootPosition = function(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 then return nil end
		return root.Position
	end,
	targetPosition = function(target)
		if typeof(target) ~= "Instance" or not target:IsA("BasePart") or not target:IsDescendantOf(Workspace) then return nil end
		return target.Position
	end,
	send = function(recipient, source, name, target, itemId)
		remote:FireClient(recipient, source, name, target, itemId)
	end,
})
remote.OnServerEvent:Connect(function(player, name, target, itemId)
	relay.handle(player, name, target, itemId)
end)
Players.PlayerRemoving:Connect(function(player) relay.forget(player) end)
