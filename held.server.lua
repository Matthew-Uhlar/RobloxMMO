-- HeldItems: builds the replicated model of each player's held item. See docs/DEPTH-CONTRACT.md §26.
-- server.server.lua owns the choice (the `hold` verb, p.held, auto tool switches)
-- and publishes it as the player attribute HeldItem ("" = empty hands). This
-- script turns that id into a small welded model (Data.Held.spec: <= 8 parts,
-- tier-coloured head, rarity trim, a glowing inlay from Epic up) parented to the
-- character as Model "HeldItem", welded at RightGripAttachment (bows and shields
-- at LeftGripAttachment), so every client sees it and swings it with the arm.
-- Rebuilt on HeldItem change, respawn, appearance load and when the hand is
-- replaced; destroyed on CharacterRemoving / PlayerRemoving. No per-frame work.

local Builder = {}
Builder.MODEL_NAME = "HeldItem"
Builder.HAND = {R15 = {right = "RightHand", left = "LeftHand"}, R6 = {right = "Right Arm", left = "Left Arm"}}
Builder.GRIP = {right = "RightGripAttachment", left = "LeftGripAttachment"}

local function hex(h)
	h = tostring(h or "FFFFFF")
	return Color3.fromRGB(tonumber(h:sub(1, 2), 16) or 255, tonumber(h:sub(3, 4), 16) or 255, tonumber(h:sub(5, 6), 16) or 255)
end
Builder.hex = hex

function Builder.rigType(character)
	if character:FindFirstChild("UpperTorso") then return "R15" end
	if character:FindFirstChild("Torso") then return "R6" end
	return nil
end
-- The hand part an item of this spec welds to, and the grip offset in its space.
-- The grip keeps only the attachment's position: the handle runs along the
-- hand's -Z, which is the frame every swing in animate.client.lua is posed for.
function Builder.gripFor(character, side)
	local rig = Builder.rigType(character)
	local hand = rig and character:FindFirstChild(Builder.HAND[rig][side])
	if not hand or not hand:IsA("BasePart") then return nil end
	local grip = hand:FindFirstChild(Builder.GRIP[side])
	local offset = if grip and grip:IsA("Attachment") then CFrame.new(grip.Position) else CFrame.new(0, -hand.Size.Y / 2, 0)
	return hand, offset
end

-- Builds (but does not parent) the model for itemId on character. Returns model, hand.
function Builder.build(Data, character, itemId)
	local spec = Data.Held.spec(itemId)
	if not spec then return nil end
	local hand, grip = Builder.gripFor(character, spec.hand)
	if not hand then return nil end
	local model = Instance.new("Model")
	model.Name = Builder.MODEL_NAME
	model:SetAttribute("ItemId", spec.id)
	model:SetAttribute("HeldClass", spec.class)
	model:SetAttribute("Hand", spec.hand)
	for _, ps in ipairs(spec.parts) do
		local part = Instance.new("Part")
		part.Name = ps.name
		part.Size = Vector3.new(ps.size[1], ps.size[2], ps.size[3])
		part.Shape = if ps.shape == "Ball" then Enum.PartType.Ball else Enum.PartType.Block
		part.Material = Enum.Material[ps.material] or Enum.Material.Metal
		part.Color = hex(ps.colour)
		part.CanCollide, part.CanQuery, part.CanTouch, part.Massless, part.CastShadow = false, false, false, true, false
		part.Anchored = false
		if ps.material == "Neon" then part.Transparency = 0.1 end
		local c0 = grip * CFrame.new(ps.offset[1], ps.offset[2], ps.offset[3])
		part.CFrame = hand.CFrame * c0
		local weld = Instance.new("Weld")
		weld.Name = "HeldWeld"
		weld.Part0, weld.Part1, weld.C0 = hand, part, c0
		weld.Parent = part
		part.Parent = model
	end
	return model, hand
end

-- Per-player lifecycle.
-- watchHand(hand, onGone) -> connection (default: the hand's AncestryChanged to nil).
function Builder.create(Data, watchHand)
	watchHand = watchHand or function(hand, onGone)
		return hand.AncestryChanged:Connect(function(_, parent) if parent == nil then onGone() end end)
	end
	local S = {models = {}, handConns = {}, conns = {}}
	local function clear(player)
		local conn = S.handConns[player]
		if conn then conn:Disconnect(); S.handConns[player] = nil end
		local model = S.models[player]
		if model then model:Destroy(); S.models[player] = nil end
	end
	S.clear = clear
	function S.refresh(player)
		clear(player)
		local character = player.Character
		local id = player:GetAttribute("HeldItem")
		if not character or type(id) ~= "string" or id == "" then return nil end
		local model, hand = Builder.build(Data, character, id)
		if not model then return nil end
		model.Parent = character
		S.models[player] = model
		-- Appearance loads and package swaps replace the hand: weld to the new one.
		S.handConns[player] = watchHand(hand, function()
			if S.models[player] == model then task.defer(S.refresh, player) end
		end)
		return model
	end
	function S.track(player)
		local list = {
			player:GetAttributeChangedSignal("HeldItem"):Connect(function() S.refresh(player) end),
			player.CharacterAdded:Connect(function(character)
				local rig = character:WaitForChild("Humanoid", 10) and Builder.rigType(character)
				if not rig then character:WaitForChild("RightHand", 5) end
				if player.Character == character then S.refresh(player) end
			end),
			player.CharacterRemoving:Connect(function() clear(player) end),
		}
		if player.CharacterAppearanceLoaded then
			table.insert(list, player.CharacterAppearanceLoaded:Connect(function() S.refresh(player) end))
		end
		S.conns[player] = list
		if player.Character then task.defer(S.refresh, player) end
	end
	function S.forget(player)
		for _, c in ipairs(S.conns[player] or {}) do c:Disconnect() end
		S.conns[player] = nil
		clear(player)
	end
	return S
end

if __HeldServerHarness then
	__HeldServerHarness(Builder)
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Data = require(ReplicatedStorage:WaitForChild("AetherData"))

local state = Builder.create(Data)
Players.PlayerAdded:Connect(state.track)
for _, player in ipairs(Players:GetPlayers()) do state.track(player) end
Players.PlayerRemoving:Connect(state.forget)
