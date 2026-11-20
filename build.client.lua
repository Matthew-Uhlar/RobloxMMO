-- Island Builder: build-mode input for free-form placement on the home island.
-- The Journal's Construction page starts a session through local player
-- attributes (IslandBuildMode "place"|"remove", IslandBuildProp, bumped
-- IslandBuildRequest). A translucent ghost snaps to the Data.Island grid under
-- the mouse, the last touch tap, or the screen centre on gamepad, tinted green
-- or red by the same rules the server re-checks. Confirm hands the request back
-- through IslandPlaceRequest/IslandPickupRequest (+ bumped counters), and the
-- atlas sends the verb. R / RB / the Rotate button turn the prop; Esc / Q / B /
-- Cancel leave build mode. Nothing here is trusted by the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Input = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Actions = game:GetService("ContextActionService")
local player = Players.LocalPlayer
local okData, Data = pcall(require, ReplicatedStorage:WaitForChild("AetherData"))
if not okData or type(Data) ~= "table" or type(Data.Island) ~= "table" then return end
local I = Data.Island
local V, C = Vector3.new, Color3.fromHex

local B = {active=false, mode="place", rot=0, valid=false, reason="", pointer=nil, gamepad=false}
local GOOD, BAD, PICK = C("6BE0A8"), C("E8806A"), C("F9CC77")
local HEIGHT = {Fences=1.6, Paths=0.3, Lights=3.4, Garden=1.4, Banners=3.6, Statues=3.2, Structures=3, Utility=1.4}

------------------------------------------------------------------------------
-- HUD: prop name, live status and touch-friendly Rotate / Place / Cancel.
------------------------------------------------------------------------------
local function make(class, parent, props)
	local object = Instance.new(class)
	for key, value in pairs(props or {}) do object[key] = value end
	object.Parent = parent
	return object
end
-- Styled with the atlas "Aether Brass" tokens (ui.client.lua): a brass-rimmed
-- plate with a prop medallion, live status with a coloured dot and three
-- controls (Place is the gold primary action; key hints in the captions).
local DEEP, SLATE, RIM = C("0C1820"), C("1E3946"), C("557886")
local IVORY, MUTED, GOLD, BRASS, ON_GOLD = C("F7EFDC"), C("A9BDC1"), C("F3C66E"), C("C9974A"), C("2B1B05")
local WHITE = Color3.new(1, 1, 1)
local function shade(object, bottom)
	make("UIGradient", object, {Name="Sheen", Rotation=90, Color=ColorSequence.new(WHITE, Color3.new(bottom, bottom, bottom))})
end
local gui = make("ScreenGui", player:WaitForChild("PlayerGui"), {Name="IslandBuilder", ResetOnSpawn=false, Enabled=false, DisplayOrder=4})
-- Sits above the atlas action bar (bottom 40px) so health stays readable.
local bar = make("Frame", gui, {Name="BuildBar", AnchorPoint=Vector2.new(.5, 1), Position=UDim2.new(.5, 0, 1, -48),
	Size=UDim2.new(.94, 0, 0, 112), BackgroundColor3=DEEP, BackgroundTransparency=.04, BorderSizePixel=0})
make("UISizeConstraint", bar, {MaxSize=Vector2.new(480, 112)})
make("UICorner", bar, {CornerRadius=UDim.new(0, 14)})
local rim = make("UIStroke", bar, {Color=BRASS, Transparency=.05, Thickness=1.5})
make("UIGradient", rim, {Rotation=90, Color=ColorSequence.new(WHITE, Color3.new(.5, .5, .5))})
shade(bar, .72)
local medal = make("Frame", bar, {Name="Medal", Position=UDim2.fromOffset(12, 10), Size=UDim2.fromOffset(38, 38), BackgroundColor3=C("2A4D5E"), BorderSizePixel=0})
make("UICorner", medal, {CornerRadius=UDim.new(1, 0)})
make("UIStroke", medal, {Color=GOLD, Thickness=1.5})
shade(medal, .5)
for _, angle in ipairs({0, 90}) do
	make("Frame", medal, {AnchorPoint=Vector2.new(.5, .5), Position=UDim2.fromScale(.5, .5), Size=UDim2.fromScale(.12, .56), Rotation=angle, BackgroundColor3=GOLD, BorderSizePixel=0})
end
local title = make("TextLabel", bar, {Name="PropName", BackgroundTransparency=1, Position=UDim2.fromOffset(60, 9), Size=UDim2.new(1, -74, 0, 22),
	Font=Enum.Font.BuilderSansExtraBold, TextSize=17, TextColor3=IVORY, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, Text=""})
local dot = make("Frame", bar, {Name="StatusDot", Position=UDim2.fromOffset(60, 36), Size=UDim2.fromOffset(8, 8), BackgroundColor3=GOOD, BorderSizePixel=0})
make("UICorner", dot, {CornerRadius=UDim.new(1, 0)})
local status = make("TextLabel", bar, {Name="Status", BackgroundTransparency=1, Position=UDim2.fromOffset(74, 30), Size=UDim2.new(1, -88, 0, 20),
	Font=Enum.Font.BuilderSansMedium, TextSize=13, TextColor3=MUTED, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, Text=""})
status:GetPropertyChangedSignal("TextColor3"):Connect(function() dot.BackgroundColor3 = status.TextColor3 end)
local buttons = {}
for i, spec in ipairs({{"RotateButton", "Rotate  (R)"}, {"ConfirmButton", "Place"}, {"CancelButton", "Done  (Esc)"}}) do
	local primary = i == 2
	local b = make("TextButton", bar, {Name=spec[1], Text=spec[2], AutoButtonColor=true, Font=Enum.Font.BuilderSansExtraBold, TextSize=14,
		TextColor3=primary and ON_GOLD or IVORY, BackgroundColor3=primary and GOLD or SLATE, BorderSizePixel=0, Selectable=true,
		Position=UDim2.new((i - 1) / 3, if i == 1 then 12 else 4, 1, -52), Size=UDim2.new(1 / 3, -14, 0, 40)})
	make("UICorner", b, {CornerRadius=UDim.new(0, 10)})
	local edge = make("UIStroke", b, {Color=primary and C("FFE7A8") or RIM, Thickness=1})
	make("UIGradient", edge, {Rotation=90, Color=ColorSequence.new(WHITE, Color3.new(.42, .42, .42))})
	shade(b, .8)
	buttons[spec[1]] = b
end
make("Frame", bar, {Name="Rule", Position=UDim2.new(0, 12, 1, -60), Size=UDim2.new(1, -24, 0, 1), BackgroundColor3=BRASS, BackgroundTransparency=.55, BorderSizePixel=0})

------------------------------------------------------------------------------
-- Grid state from replicated attributes.
------------------------------------------------------------------------------
local function islandCenter()
	local center = player:GetAttribute("IslandCenter")
	if typeof(center) == "Vector3" then return center end
	return nil
end
local function placements() return I.decode(player:GetAttribute("IslandPlacements")) end
local function placementFolder()
	local isles = workspace:FindFirstChild("AetherIsles")
	local home = isles and isles:FindFirstChild("WayfarersRest_" .. player.UserId)
	return home and home:FindFirstChild("Placements")
end

------------------------------------------------------------------------------
-- Ghost preview (client only; anchored, non-colliding, non-queryable).
------------------------------------------------------------------------------
local function ghostPart(parent, name, size)
	return make("Part", parent, {Name=name, Size=size, Anchored=true, CanCollide=false, CanQuery=false, CanTouch=false, CastShadow=false,
		Material=Enum.Material.Neon, Transparency=.55, Color=GOOD, TopSurface=Enum.SurfaceType.Smooth, BottomSurface=Enum.SurfaceType.Smooth})
end
function B.clearGhost()
	if B.ghost then B.ghost:Destroy() end
	B.ghost = nil
	if B.highlight then B.highlight:Destroy() end
	B.highlight, B.target = nil, nil
end
function B.makeGhost()
	B.clearGhost()
	if B.mode ~= "place" then return end
	local def = I.Props[B.prop]
	local model = make("Model", workspace, {Name="IslandGhost"})
	local w, d = def.size[1] * I.CELL, def.size[2] * I.CELL
	B.slab = ghostPart(model, "Footprint", V(w - .1, .12, d - .1))
	B.body = ghostPart(model, "Volume", V(w - .5, HEIGHT[def.category] or 2, d - .5))
	B.body.Transparency = .72
	B.arrow = ghostPart(model, "Front", V(.5, .14, .5))
	B.ghost = model
end
function B.tint(color)
	for _, p in ipairs({B.slab, B.body, B.arrow}) do if p then p.Color = color end end
end

------------------------------------------------------------------------------
-- Pointer -> grid cell.
------------------------------------------------------------------------------
function B.ray()
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local point = B.pointer
	if B.gamepad or not point then
		local size = camera.ViewportSize
		point = Vector2.new(size.X / 2, size.Y / 2)
	end
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {B.ghost, player.Character}
	return workspace:Raycast(ray.Origin, ray.Direction * 400, params)
end
function B.update()
	if not B.active then return end
	local center = islandCenter()
	local hit = B.ray()
	if B.mode == "remove" then
		local node = hit and hit.Instance
		while node and not (node.ClassName == "Model" and node:GetAttribute("PlacementId")) do node = node.Parent end
		local folder = placementFolder()
		local target = if node and folder and node.Parent == folder then node else nil
		if target ~= B.targetModel then
			if B.highlight then B.highlight:Destroy() end
			B.highlight = target and make("Highlight", target, {Name="PickupHighlight", FillColor=BAD, OutlineColor=PICK, FillTransparency=.55})
			B.targetModel = target
		end
		B.target = target and target:GetAttribute("PlacementId")
		B.valid = B.target ~= nil
		B.reason = if B.target then "Pick up the " .. ((I.Props[target:GetAttribute("PropId")] or {}).name or "prop") .. "  ·  materials return in full" else "Point at a prop you placed"
		status.Text, status.TextColor3 = B.reason, B.valid and GOOD or C("BECECA")
		return
	end
	if not center or not hit then
		B.valid, B.reason = false, "Aim at your home island"
		status.Text, status.TextColor3 = B.reason, BAD
		if B.ghost then B.ghost.Parent = nil end
		return
	end
	local offset = hit.Position - center
	local x, z = I.snap(B.prop, B.rot, offset.X, offset.Z)
	B.x, B.z = x, z
	local list = placements()
	local valid, reason = I.check(I.occupancy(list), B.prop, x, z, B.rot)
	if valid then
		local count = 0
		for _, e in ipairs(list) do if e.prop == B.prop then count += 1 end end
		local def = I.Props[B.prop]
		if #list >= I.MAX_PLACEMENTS then valid, reason = false, "Your island is full"
		elseif count >= def.max then valid, reason = false, "Most " .. def.name .. " pieces placed (" .. def.max .. ")" end
	end
	B.valid, B.reason = valid, reason or "Valid spot  ·  click, tap Place or press A"
	status.Text, status.TextColor3 = B.reason, valid and GOOD or BAD
	if B.ghost then
		B.ghost.Parent = workspace
		local ox, oz, yaw = I.centerOffset(B.prop, x, z, B.rot)
		local frame = CFrame.new(center + V(ox, 0, oz)) * CFrame.Angles(0, yaw, 0)
		B.slab.CFrame = frame * CFrame.new(0, .08, 0)
		B.body.CFrame = frame * CFrame.new(0, B.body.Size.Y / 2 + .1, 0)
		B.arrow.CFrame = frame * CFrame.new(0, .2, -(I.Props[B.prop].size[2] * I.CELL / 2 - .35))
		B.tint(valid and GOOD or BAD)
	end
end

------------------------------------------------------------------------------
-- Session lifecycle.
------------------------------------------------------------------------------
-- Gamepad: A places, B leaves, RB rotates. Bound above the character controls
-- and sunk, so A does not also jump while building.
local GAMEPAD_ACTION = "AetherIslandBuild"
function B.gamepadAction(_, state, input)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
	B.gamepad = true
	if input.KeyCode == Enum.KeyCode.ButtonA then B.confirm()
	elseif input.KeyCode == Enum.KeyCode.ButtonB then B.exit()
	elseif input.KeyCode == Enum.KeyCode.ButtonR1 then B.rotate() end
	return Enum.ContextActionResult.Sink
end
function B.exit()
	if not B.active then return end
	B.active = false
	Actions:UnbindAction(GAMEPAD_ACTION)
	if B.step then B.step:Disconnect() end
	B.step = nil
	B.clearGhost()
	B.targetModel = nil
	gui.Enabled = false
end
function B.enter(mode, propId)
	B.exit()
	if mode == "place" and not I.Props[propId] then return end
	if mode ~= "place" and mode ~= "remove" then return end
	B.mode, B.prop, B.rot, B.active = mode, propId, 0, true
	B.gamepad = Input.GamepadEnabled and not Input.MouseEnabled and not Input.TouchEnabled
	B.makeGhost()
	title.Text = if mode == "place" then "Placing  ·  " .. I.Props[propId].name else "Pick up mode"
	buttons.ConfirmButton.Text = if mode == "place" then "Place" else "Pick up"
	buttons.RotateButton.Visible = mode == "place"
	gui.Enabled = true
	Actions:BindActionAtPriority(GAMEPAD_ACTION, B.gamepadAction, false, Enum.ContextActionPriority.High.Value + 1,
		Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonR1)
	B.step = RunService.RenderStepped:Connect(B.update)
	B.update()
end
function B.rotate()
	if not B.active or B.mode ~= "place" then return end
	B.rot = (B.rot + 1) % 4
	B.update()
end
function B.confirm()
	if not B.active then return end
	B.update()
	if not B.valid then return end
	if B.mode == "place" then
		player:SetAttribute("IslandPlaceRequest", B.prop .. ":" .. B.x .. ":" .. B.z .. ":" .. B.rot)
		player:SetAttribute("IslandPlaceCount", (tonumber(player:GetAttribute("IslandPlaceCount")) or 0) + 1)
	else
		player:SetAttribute("IslandPickupRequest", tostring(B.target))
		player:SetAttribute("IslandPickupCount", (tonumber(player:GetAttribute("IslandPickupCount")) or 0) + 1)
	end
end
buttons.RotateButton.Activated:Connect(B.rotate)
buttons.ConfirmButton.Activated:Connect(B.confirm)
buttons.CancelButton.Activated:Connect(B.exit)

player:GetAttributeChangedSignal("IslandBuildRequest"):Connect(function()
	local mode, prop = player:GetAttribute("IslandBuildMode"), player:GetAttribute("IslandBuildProp")
	B.enter(if type(mode) == "string" then mode else "", if type(prop) == "string" then prop else "")
end)
player:GetAttributeChangedSignal("IslandPlacements"):Connect(function() if B.active then B.update() end end)
player.CharacterRemoving:Connect(B.exit)

Input.InputChanged:Connect(function(input)
	if not B.active then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		B.pointer, B.gamepad = Vector2.new(input.Position.X, input.Position.Y), false
	elseif input.UserInputType == Enum.UserInputType.Gamepad1 then
		B.gamepad = true
	end
end)
Input.TouchTapInWorld:Connect(function(position, processed)
	if not B.active or processed then return end
	B.pointer, B.gamepad = position, false
	B.update()
end)
Input.InputBegan:Connect(function(input, processed)
	if not B.active then return end
	local key = input.KeyCode
	if key == Enum.KeyCode.Escape or (key == Enum.KeyCode.Q and not processed) then
		B.exit()
	elseif processed then
		return
	elseif key == Enum.KeyCode.R then
		B.rotate()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		B.pointer, B.gamepad = Vector2.new(input.Position.X, input.Position.Y), false
		B.confirm()
	end
end)
