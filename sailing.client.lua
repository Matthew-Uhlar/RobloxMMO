-- Skysailing client (StarterPlayerScripts.IsleSailing; docs/DEPTH-CONTRACT.md §51).
--   * Helm: while your SailVessel role is "helm" you own the hull's physics.
--     W / S set the sails (0 = heaved to .. 1 = full), A / D steer, Q / E climb.
--     Speed = the ship's top speed x SS.speedFactor(wind, relative wind, trim,
--     sail efficiency) from the §50 wind field (A.windDir / A.windAt on server
--     time, the region's base and the IsleWeather state), never above the cap
--     the server checks (VesselState). Storms add turbulence (yaw / pitch jolts).
--   * Ship HUD (bottom centre while aboard): heading (compass + degrees),
--     speed in knots, a wind arrow relative to the bow with its strength, hull
--     integrity, sail trim (helm / sails crew: [ and ] or the buttons), your role,
--     the contract strip, and context buttons: Fire (gunners), Salvage / Fish
--     (heaved to over a wreck / reef), Dock (captain at a berth), Leave (crew).
--   * Shipwright panel (SailShipwright bump): each slot's next component, its
--     level and costs; Build sends shipBuild. Harbour board (SailBoardPort):
--     every route from that port with distance, time, XP and purse coins.
--   * Look: forged hull / mast / helm / cannon meshes (MeshForgeLocal "visual",
--     welded locally to the hosts), local cloth sails on each SailSlot (an
--     EditableMesh grid whose belly follows the local wind and the trim; a
--     curved fabric fallback), rigging beams, a wake and lantern glow, a muzzle
--     flash for every VesselFire. Reduced motion calms the cloth and turbulence.
-- Nothing here grants anything: the server checks every verb and every pose.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local AssetService = game:GetService("AssetService")
local player = Players.LocalPlayer

local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local T = require(ReplicatedStorage:WaitForChild("AetherUiTheme"))
local okA, A = pcall(function() return require(ReplicatedStorage:WaitForChild("AetherAmbience", 10)) end)
if not okA then A = nil end
local SS = Data.Skysailing
local make = T.make

local function channel(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then return existing end
	local created = Instance.new("BindableEvent")
	created.Name = name
	created.Parent = ReplicatedStorage
	return created
end
local actions, snapshots = channel("IsleActionLocal"), channel("IsleSnapshotLocal")
local function send(verb, item) actions:Fire(verb, item) end
local function gesture(name) local g = ReplicatedStorage:FindFirstChild("IsleGestureLocal"); if g then g:Fire(name) end end
local function tbl(v) return if type(v) == "table" then v else {} end
local function reduced() return T.reducedMotion and T.reducedMotion(player) or false end
local function serverNow()
	local ok, t = pcall(function() return workspace:GetServerTimeNow() end)
	return if ok and t then t else os.time()
end
local function rootPart()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local S = {state = nil, vessel = nil, role = nil, throttle = 0, yaw = nil, climb = 0, ships = {}, lastBoard = nil, lastWright = nil}
S.RANGE = 320 -- ships drawn (meshes, cloth) within this many studs

------------------------------------------------------------------------------
-- Wind at a point (the §50 field) and the local weather.
------------------------------------------------------------------------------
local function windAt(pos)
	local region = SS.regionAt(pos.X, pos.Z)
	local weather = SS.weatherFor(workspace:GetAttribute("IsleWeather"), region)
	if not A then return 1, 0.8, 0.6, weather end
	local t = serverNow() - (A.EPOCH or 0)
	local dx, dz = A.windDir(t)
	local base = A.Regions and A.Regions[region] and A.Regions[region].wind or 1
	return A.windAtDir(t, pos.X, pos.Z, base, weather, dx, dz), dx, dz, weather
end

------------------------------------------------------------------------------
-- HUD
------------------------------------------------------------------------------
local gui = make("ScreenGui", player:WaitForChild("PlayerGui"), {Name = "IsleSailing", ResetOnSpawn = false, DisplayOrder = 9,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
local ACCENT = Color3.fromHex("4AA8E8")
local function panel(parent, props)
	local f = make("Frame", parent, props)
	f.BorderSizePixel = 0
	make("UICorner", f, {CornerRadius = UDim.new(0, 10)})
	make("UIStroke", f, {Color = ACCENT, Thickness = 2})
	make("UIGradient", f, {Rotation = 90, Transparency = NumberSequence.new(0, 0.12)})
	return f
end
local hud = panel(gui, {Name = "ShipHud", Visible = false, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -118),
	Size = UDim2.fromOffset(420, 132), BackgroundColor3 = T.color.panel, BackgroundTransparency = 0.06})
local title = T.label(hud, {Name = "Title", Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 18), Text = "SKYSKIFF", Font = T.font.display, TextSize = 14,
	TextColor3 = T.color.gold})
-- Compass dial with a heading needle and the wind arrow (relative to the bow).
local dial = make("Frame", hud, {Name = "Dial", Position = UDim2.fromOffset(12, 28), Size = UDim2.fromOffset(92, 92), BackgroundColor3 = T.color.void, BorderSizePixel = 0})
make("UICorner", dial, {CornerRadius = UDim.new(1, 0)})
make("UIStroke", dial, {Color = T.color.frame, Thickness = 2})
local function letter(text, x, y) T.label(dial, {Text = text, Position = UDim2.new(x, -6, y, -7), Size = UDim2.fromOffset(12, 14), TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = T.color.dim}) end
letter("N", 0.5, 0.1); letter("E", 0.9, 0.5); letter("S", 0.5, 0.9); letter("W", 0.1, 0.5)
local needle = make("Frame", dial, {Name = "Heading", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 36),
	BackgroundColor3 = T.color.gold, BorderSizePixel = 0})
local windArrow = make("Frame", dial, {Name = "Wind", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(3, 30),
	BackgroundColor3 = T.color.mint, BorderSizePixel = 0})
local readout = T.label(hud, {Name = "Readout", Position = UDim2.fromOffset(114, 28), Size = UDim2.new(1, -126, 0, 18), Text = "", TextSize = 14, Font = T.font.label})
local windText = T.label(hud, {Name = "WindText", Position = UDim2.fromOffset(114, 46), Size = UDim2.new(1, -126, 0, 16), Text = "", TextSize = 12, TextColor3 = T.color.dim})
local hullBack = make("Frame", hud, {Name = "Hull", Position = UDim2.fromOffset(114, 66), Size = UDim2.new(1, -126, 0, 12), BackgroundColor3 = T.color.void, BorderSizePixel = 0})
make("UICorner", hullBack, {CornerRadius = UDim.new(0, 5)})
local hullFill = make("Frame", hullBack, {Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.color.defense, BorderSizePixel = 0})
make("UICorner", hullFill, {CornerRadius = UDim.new(0, 5)})
local hullText = T.label(hullBack, {Name = "Text", Size = UDim2.fromScale(1, 1), Text = "", TextSize = 10, TextXAlignment = Enum.TextXAlignment.Center})
local trimText = T.label(hud, {Name = "Trim", Position = UDim2.fromOffset(114, 82), Size = UDim2.fromOffset(150, 16), Text = "", TextSize = 12})
local contractText = T.label(hud, {Name = "Contract", Position = UDim2.fromOffset(114, 98), Size = UDim2.new(1, -126, 0, 14), Text = "", TextSize = 11, TextColor3 = T.color.goldSoft})
local buttons = make("Frame", hud, {Name = "Buttons", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 6), Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1})
make("UIListLayout", buttons, {FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6)})
local function button(caption, onClick, tone)
	local b = T.button(buttons, caption, {size = UDim2.fromOffset(78, 34), tone = tone})
	b.Visible = false
	b.Activated:Connect(onClick)
	return b
end
local trimDown = T.button(hud, "–", {size = UDim2.fromOffset(26, 18), position = UDim2.fromOffset(268, 81)})
local trimUp = T.button(hud, "+", {size = UDim2.fromOffset(26, 18), position = UDim2.fromOffset(298, 81)})
local function setTrim(delta)
	local v = S.vessel
	if not v then return end
	local now = math.clamp(math.floor(((v.model:GetAttribute("SailTrim") or 0.5) + delta) * 100 + 0.5), 0, 100)
	send("sailTrim", tostring(now))
	if string.sub(S.role or "", 1, 5) == "sails" then gesture("haul") end
end
trimDown.Activated:Connect(function() setTrim(-0.1) end)
trimUp.Activated:Connect(function() setTrim(0.1) end)
local fireB = button("Fire", function()
	local cam = workspace.CurrentCamera
	local look = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
	send("sailFire", tostring(math.floor(math.deg(math.atan2(look.X, -look.Z)) + 0.5)))
end, "primary")
local salvageB = button("Salvage", function() send("sailSalvage"); gesture("grapple") end)
local fishB = button("Fish", function() send("sailFish") end)
local dockB = button("Dock", function() send("sailDock") end, "primary")
local leaveB = button("Leave", function() send("sailLeave") end)

------------------------------------------------------------------------------
-- Pickers: the shipwright's plans and the harbour board.
------------------------------------------------------------------------------
local picker = panel(gui, {Name = "SailPicker", Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(460, 360), BackgroundColor3 = T.color.panel, BackgroundTransparency = 0.04})
local pickTitle = T.label(picker, {Name = "Title", Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -60, 0, 22), Text = "", Font = T.font.display, TextSize = 15, TextColor3 = T.color.gold})
local close = T.button(picker, "✕", {size = UDim2.fromOffset(30, 26), position = UDim2.new(1, -40, 0, 8)})
close.Activated:Connect(function() picker.Visible = false end)
local list = make("ScrollingFrame", picker, {Name = "List", Position = UDim2.fromOffset(10, 40), Size = UDim2.new(1, -20, 1, -50), BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new()})
make("UIListLayout", list, {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder})
local function clearList() for _, c in ipairs(list:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end end
local function row(order, text, sub, caption, enabled, onClick)
	local r = make("Frame", list, {LayoutOrder = order, Size = UDim2.new(1, -8, 0, 52), BackgroundColor3 = T.color.inset, BorderSizePixel = 0})
	make("UICorner", r, {CornerRadius = UDim.new(0, 6)})
	T.label(r, {Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -120, 0, 20), Text = text, Font = T.font.label, TextSize = 14})
	T.label(r, {Position = UDim2.fromOffset(10, 25), Size = UDim2.new(1, -120, 0, 22), Text = sub, TextSize = 11, TextColor3 = T.color.dim, TextWrapped = true})
	if caption then
		local b = T.button(r, caption, {size = UDim2.fromOffset(96, 34), position = UDim2.new(1, -104, 0.5, -17), tone = if enabled then "primary" else "secondary"})
		b.AutoButtonColor = enabled
		b.Activated:Connect(function() if enabled then onClick() end end)
	end
end
local function costText(costs)
	local parts = {}
	for id, n in pairs(costs) do table.insert(parts, n .. " " .. (Data.Items[id] and Data.Items[id].name or id)) end
	table.sort(parts)
	return table.concat(parts, ", ")
end
local function drawShipwright()
	local s = tbl(S.state)
	pickTitle.Text = "SHIPWRIGHT'S SLIP"
	clearList()
	local spec = s.spec
	row(0, if spec then spec.name .. " · hull " .. tostring(s.hullHp or spec.hp) .. "/" .. spec.hp else "No ship yet",
		if spec then string.format("Top speed %.0f · crew %d · hold %d crates · cannons %s", spec.speed, spec.crew, spec.cargo, if spec.cannon > 0 then tostring(spec.cannon) else "none")
		else "Lay a Skyskiff hull, then sails and a keel, and you can sail.", if spec then "Repair" else nil, true, function() send("sailRepair") end)
	for i, slot in ipairs(SS.SLOTS) do
		local nxt = tbl(s.next)[slot]
		local c = nxt and SS.ComponentById[nxt.id]
		if c then
			row(i, SS.SLOT_NAMES[slot] .. ": " .. c.name .. " (Skysailing " .. c.level .. ")", costText(c.costs) .. "  ·  +" .. c.xp .. " XP" .. (if nxt.ok then "" else "  ·  " .. tostring(nxt.why)),
				"Build", nxt.ok == true, function() send("shipBuild", c.id) end)
		else
			local have = s.ship and s.ship[slot] and SS.ComponentById[s.ship[slot]]
			row(i, SS.SLOT_NAMES[slot] .. ": " .. (if have then have.name else "—"), "The finest the shipwrights can fit.", nil, false, nil)
		end
	end
	picker.Visible = true
end
local function drawBoard(portId)
	local s = tbl(S.state)
	local port = SS.PortById[portId]
	if not port then return end
	pickTitle.Text = string.upper(port.name)
	clearList()
	local c = s.contract
	if c then
		local route = SS.RouteById[c.route]
		row(0, "Current: " .. c.crates .. " crates to the " .. SS.PortById[route.to].name, string.format("%ds left · %s · bond %d", c.left, if c.loaded then "loaded" else "in the warehouse", c.bond),
			"Abandon", true, function() send("sailAbandon") end)
	end
	local level = s.level or 1
	local cargo = s.spec and s.spec.cargo or 0
	local purse = tbl(s.purse)
	for i, r in ipairs(SS.Routes) do
		if r.from == portId then
			local open = level >= r.level and cargo > 0 and not c
			row(i, "To the " .. SS.PortById[r.to].name .. (if level < r.level then " (Skysailing " .. r.level .. ")" else ""),
				string.format("%d studs · %ds · %d crates · +%d XP · %d coins (purse %d/%d)", math.floor(r.distance), SS.contractLimit(r), math.max(1, cargo),
					SS.contractXp(r, math.max(1, cargo), level), SS.contractCoins(r, math.max(1, cargo)), purse.paid or 0, purse.cap or 0),
				"Accept", open, function() send("sailContract", r.id) end)
		end
	end
	picker.Visible = true
end
player:GetAttributeChangedSignal("SailShipwright"):Connect(function() task.defer(drawShipwright) end)
player:GetAttributeChangedSignal("SailBoardPort"):Connect(function()
	local port = string.match(tostring(player:GetAttribute("SailBoardPort") or ""), "^(%a+):")
	if port then task.defer(drawBoard, port) end
end)

------------------------------------------------------------------------------
-- Ship visuals: forged meshes, cloth sails, rigging, muzzle flashes.
------------------------------------------------------------------------------
local localFolder = workspace:FindFirstChild("IsleSailLocal") or Instance.new("Folder")
localFolder.Name = "IsleSailLocal"
localFolder.Parent = workspace
local function forge(host)
	local api = ReplicatedStorage:FindFirstChild("MeshForgeLocal")
	local shape = host:GetAttribute("ShipShape")
	if not api or type(shape) ~= "string" then return nil end
	-- MeshForgeLocal reads the Shape attribute; ShapeManual keeps the forge's own scan away.
	host:SetAttribute("ShapeManual", true)
	host:SetAttribute("Shape", shape)
	local ok, clone, _, token = pcall(api.Invoke, api, "visual", host)
	if not ok or not clone then return nil end
	local okAccept, accepted = pcall(api.Invoke, api, "accept", token)
	if not okAccept or not accepted then pcall(api.Invoke, api, "release", token); clone:Destroy() return nil end
	clone.Anchored, clone.CanCollide, clone.CanQuery, clone.CanTouch, clone.Massless = false, false, false, false, true
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = host, clone
	weld.Parent = clone
	clone.Parent = localFolder
	host.LocalTransparencyModifier = 1
	return {clone = clone, token = token, host = host}
end
-- Cloth: a COLS x ROWS grid of vertices in the slot's plane, bellied along +Z (downwind).
local COLS, ROWS = 9, 7
local function cloth(slot)
	local size = slot.Size
	local c = {slot = slot, w = size.X, h = size.Y}
	local ok = pcall(function()
		local mesh = AssetService:CreateEditableMesh()
		c.ids = {}
		for r = 0, ROWS do
			for k = 0, COLS do
				-- Start with a gentle belly so the mesh has depth (its MeshSize is never zero).
				local id = mesh:AddVertex(Vector3.new((k / COLS - 0.5) * c.w, (0.5 - r / ROWS) * c.h, 0.3 * math.sin(math.pi * k / COLS) * math.sin(math.pi * r / ROWS)))
				c.ids[r * (COLS + 1) + k + 1] = id
			end
		end
		for r = 0, ROWS - 1 do
			for k = 0, COLS - 1 do
				local a, b = c.ids[r * (COLS + 1) + k + 1], c.ids[r * (COLS + 1) + k + 2]
				local d, e = c.ids[(r + 1) * (COLS + 1) + k + 1], c.ids[(r + 1) * (COLS + 1) + k + 2]
				mesh:AddTriangle(a, d, b); mesh:AddTriangle(b, d, e)
				mesh:AddTriangle(a, b, d); mesh:AddTriangle(b, e, d) -- both faces (cloth is seen from both sides)
			end
		end
		local part = AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
		c.mesh, c.part = mesh, part
	end)
	if not ok or not c.part then
		-- Fallback: a curved pair of fabric panels.
		local p = Instance.new("Part")
		p.Size = Vector3.new(c.w, c.h, 0.15)
		c.part, c.fallback = p, true
	end
	local p = c.part
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, true
	p.Material, p.Color = Enum.Material.Fabric, Color3.fromHex("EFE6D3")
	p.Name = "Cloth sail"
	p.Parent = localFolder
	return c
end
local function updateCloth(c, wind, rel, trim, t, gust)
	local belly = SS.billow(wind, rel, trim, reduced())
	if c.mesh then
		local flutter = if reduced() then 0 else 0.18 * gust
		for r = 0, ROWS do
			local v = r / ROWS
			for k = 0, COLS do
				local u = k / COLS
				-- Belly: deepest mid-sail, tied at the yard (top) and the luff edges.
				local z = belly * math.sin(math.pi * u) * math.sin(math.pi * (0.15 + 0.85 * v)) + flutter * math.sin(6 * t + u * 9 + v * 5) * v
				pcall(c.mesh.SetPosition, c.mesh, c.ids[r * (COLS + 1) + k + 1], Vector3.new((u - 0.5) * c.w, (0.5 - v) * c.h, z))
			end
		end
		c.part.CFrame = c.slot.CFrame
	else
		c.part.CFrame = c.slot.CFrame * CFrame.new(0, 0, belly * 0.5) * CFrame.Angles(0, 0, 0)
		c.part.Size = Vector3.new(c.w, c.h, 0.15 + belly * 0.2)
	end
end
local function release(ship)
	ship.released = true
	local api = ReplicatedStorage:FindFirstChild("MeshForgeLocal")
	for _, m in ipairs(ship.meshes) do
		if api then pcall(api.Invoke, api, "release", m.token) end
		pcall(m.clone.Destroy, m.clone)
		if m.host.Parent then m.host.LocalTransparencyModifier = 0 end
	end
	for _, c in ipairs(ship.cloth) do
		pcall(c.part.Destroy, c.part)
		if c.mesh then pcall(c.mesh.Destroy, c.mesh) end
	end
	for _, x in ipairs(ship.extras) do pcall(x.Destroy, x) end
	ship.meshes, ship.cloth, ship.extras = {}, {}, {}
	if S.ships[ship.model] == ship then S.ships[ship.model] = nil end
end
-- Builds a ship's local dressing (forging can yield, so it runs in its own
-- thread); anything finished after the ship was released is torn down at once.
local function dress(ship)
	local model = ship.model
	for _, part in ipairs(model:GetChildren()) do
		if ship.released then break end
		if part:IsA("BasePart") then
			if part:GetAttribute("ShipShape") then
				local m = forge(part)
				if m then table.insert(ship.meshes, m) end
			end
			if part:GetAttribute("SailSlot") then table.insert(ship.cloth, cloth(part)) end
		end
	end
	if ship.released then release(ship) return end
	-- Rigging: beams from each mast top to the rails (local attachments).
	local hullPart = model:FindFirstChild("Hull")
	if hullPart then
		for _, mast in ipairs(model:GetChildren()) do
			if mast:IsA("BasePart") and string.sub(mast.Name, 1, 4) == "Mast" then
				local top = Instance.new("Attachment")
				top.Position = Vector3.new(0, mast.Size.Y * 0.45, 0)
				top.Parent = mast
				table.insert(ship.extras, top)
				for _, x in ipairs({-1, 1}) do
					for _, z in ipairs({-0.3, 0.3}) do
						local foot = Instance.new("Attachment")
						foot.Position = Vector3.new(x * hullPart.Size.X * 0.45, hullPart.Size.Y * 0.5 + 0.6, z * hullPart.Size.Z * 0.4)
						foot.Parent = hullPart
						local line = Instance.new("Beam")
						line.Attachment0, line.Attachment1 = top, foot
						line.Width0, line.Width1, line.FaceCamera, line.Segments = 0.06, 0.06, true, 1
						line.Color = ColorSequence.new(Color3.fromHex("C9B48A"))
						line.Transparency = NumberSequence.new(0.1)
						line.Parent = hullPart
						table.insert(ship.extras, foot)
						table.insert(ship.extras, line)
					end
				end
			end
		end
		-- A soft aether wake under the keel.
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Position, a1.Position = Vector3.new(-0.8, -hullPart.Size.Y * 0.5, hullPart.Size.Z * 0.45), Vector3.new(0.8, -hullPart.Size.Y * 0.5, hullPart.Size.Z * 0.45)
		a0.Parent, a1.Parent = hullPart, hullPart
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1, trail.Lifetime = a0, a1, if reduced() then 0.6 else 1.4
		trail.Color = ColorSequence.new(Color3.fromHex("BFEFFF"), Color3.fromHex("4AA8E8"))
		trail.Transparency = NumberSequence.new(0.35, 1)
		trail.LightEmission, trail.FaceCamera = 0.6, true
		trail.Parent = hullPart
		for _, x in ipairs({a0, a1, trail}) do table.insert(ship.extras, x) end
	end
	if ship.released then release(ship) end
end
local function shipFor(model)
	local ship = S.ships[model]
	if ship then return ship end
	ship = {model = model, meshes = {}, cloth = {}, extras = {}, fireSeq = nil}
	S.ships[model] = ship
	task.spawn(dress, ship)
	return ship
end
local function flash(ship)
	local text = ship.model:GetAttribute("VesselFire")
	if type(text) ~= "string" or text == ship.fireSeq then return end
	ship.fireSeq = text
	local _, dx, dz = string.match(text, "^(%d+):([%-%d%.]+):([%-%d%.]+)")
	local hullPart = ship.model:FindFirstChild("Hull")
	if not hullPart or not dx then return end
	local dir = Vector3.new(tonumber(dx), 0, tonumber(dz))
	local at = hullPart.Position + Vector3.new(0, hullPart.Size.Y, 0) + dir * (hullPart.Size.X * 0.6)
	local p = Instance.new("Part")
	p.Shape, p.Material, p.Color = Enum.PartType.Ball, Enum.Material.Neon, Color3.fromHex("FFB347")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Size, p.CFrame = Vector3.new(2.4, 2.4, 2.4), CFrame.new(at)
	p.Parent = localFolder
	local smoke = Instance.new("ParticleEmitter")
	smoke.Rate, smoke.Lifetime, smoke.Speed = 0, NumberRange.new(0.8, 1.4), NumberRange.new(4, 8)
	smoke.Color = ColorSequence.new(Color3.fromHex("D8D2C4"))
	smoke.Size = NumberSequence.new(1.2, 3)
	smoke.Transparency = NumberSequence.new(0.3, 1)
	smoke.Parent = p
	pcall(function() smoke:Emit(if reduced() then 6 else 16) end)
	task.delay(0.12, function() p.Transparency = 1 end)
	task.delay(1.6, function() p:Destroy() end)
end

------------------------------------------------------------------------------
-- Vessel lookup and the helm drive.
------------------------------------------------------------------------------
local function vessels()
	local f = workspace:FindFirstChild("IsleVessels")
	return if f then f:GetChildren() else {}
end
local function myVessel()
	local text = player:GetAttribute("SailVessel")
	if type(text) ~= "string" or text == "" then return nil, nil end
	local id, role = string.match(text, "^(%d+):%d+:(%w+)$")
	id = tonumber(id)
	for _, m in ipairs(vessels()) do
		if m:GetAttribute("VesselId") == id then return {model = m, root = m:FindFirstChild("Hull")}, role end
	end
	return nil, role
end
local keys = {W = false, S = false, A = false, D = false, Q = false, E = false}
Input.InputBegan:Connect(function(io, processed)
	if processed then return end
	local name = io.KeyCode.Name
	if keys[name] ~= nil then keys[name] = true end
	if S.vessel and (name == "LeftBracket" or name == "RightBracket") then setTrim(if name == "LeftBracket" then -0.1 else 0.1) end
end)
Input.InputEnded:Connect(function(io)
	local name = io.KeyCode.Name
	if keys[name] ~= nil then keys[name] = false end
end)
local function drive(v, dt, t)
	local root = v.root
	if not root then return end
	local lv, ao = root:FindFirstChild("Drive"), root:FindFirstChild("Heading")
	if not lv or not ao then return end
	local spec = tbl(S.state).spec
	local st = SS.parseState(v.model:GetAttribute("VesselState"))
	local cap = st and st.cap or (spec and spec.speed) or 20
	local turn = spec and spec.turn or 40
	-- Touch / gamepad: the humanoid's move vector steers when no keys are held.
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local move = humanoid and humanoid.MoveDirection or Vector3.zero
	local fwd = (if keys.W then 1 else 0) - (if keys.S then 1 else 0)
	local steer = (if keys.D then 1 else 0) - (if keys.A then 1 else 0)
	if fwd == 0 and steer == 0 and move.Magnitude > 0.1 then
		local cam = workspace.CurrentCamera
		local local3 = cam and cam.CFrame:VectorToObjectSpace(move) or move
		fwd, steer = -math.sign(local3.Z) * (if math.abs(local3.Z) > 0.3 then 1 else 0), math.sign(local3.X) * (if math.abs(local3.X) > 0.3 then 1 else 0)
	end
	S.throttle = math.clamp(S.throttle + fwd * dt * 0.6, 0, 1)
	S.yaw = (S.yaw or select(2, root.CFrame:ToEulerAnglesYXZ())) - steer * math.rad(turn) * dt
	S.climb = ((if keys.E then 1 else 0) - (if keys.Q then 1 else 0)) * SS.CLIMB_MAX * 0.8
	local wind, wx, wz, weather = windAt(root.Position)
	local look = root.CFrame.LookVector
	local rel = SS.relWind(look.X, look.Z, wx, wz)
	local trim = v.model:GetAttribute("SailTrim") or 0.5
	local factor = SS.speedFactor(wind, rel, trim, spec and spec.windEff or 0.7)
	local speed = math.min(cap, cap * factor * S.throttle)
	local jolt = 0
	if not reduced() then jolt = (SS.WEATHER_TURBULENCE[weather] or 0) * 0.06 * math.sin(t * 2.7) * math.sin(t * 1.3) end
	local bank = -steer * 0.12 * math.min(1, speed / math.max(1, cap))
	ao.CFrame = CFrame.Angles(0, S.yaw + jolt, 0) * CFrame.Angles(jolt * 0.6, 0, bank)
	local heading = CFrame.Angles(0, S.yaw, 0).LookVector
	lv.VectorVelocity = heading * speed + Vector3.new(0, S.climb + jolt * 8, 0)
end

------------------------------------------------------------------------------
-- The frame: HUD, drive, cloth.
------------------------------------------------------------------------------
local function near(kind, pos, range)
	return SS.chartsNear({x = pos.X, y = pos.Y, z = pos.Z}, range, kind)[1]
end
local clothAt = 0
RunService.Heartbeat:Connect(function(dt)
	local t = os.clock()
	local v, role = myVessel()
	if v and (not S.vessel or S.vessel.model ~= v.model) then S.yaw = nil; S.throttle = 0 end
	if role ~= S.role and role == "helm" then gesture("helm") end
	S.vessel, S.role = v, role
	if v and role == "helm" then pcall(drive, v, dt, t) end
	-- Visuals for every ship within range.
	local here = rootPart()
	local seen = {}
	for _, m in ipairs(vessels()) do
		local hullPart = m:FindFirstChild("Hull")
		if hullPart and here and (hullPart.Position - here.Position).Magnitude <= S.RANGE then
			seen[m] = true
			local ship = shipFor(m)
			flash(ship)
		end
	end
	for model, ship in pairs(S.ships) do if not seen[model] or not model.Parent then release(ship) end end
	if t >= clothAt then
		clothAt = t + (if reduced() then 1 / 10 else 1 / 30)
		for _, ship in pairs(S.ships) do
			local hullPart = ship.model:FindFirstChild("Hull")
			if hullPart then
				local wind, wx, wz = windAt(hullPart.Position)
				local look = hullPart.CFrame.LookVector
				local rel = SS.relWind(look.X, look.Z, wx, wz)
				local trim = ship.model:GetAttribute("SailTrim") or 0.5
				local gust = if A then A.gust(serverNow() - (A.EPOCH or 0), hullPart.Position.X, hullPart.Position.Z) else 0.3
				for _, c in ipairs(ship.cloth) do if c.slot.Parent then pcall(updateCloth, c, wind, rel, trim, t, gust) end end
			end
		end
	end
	-- HUD
	hud.Visible = v ~= nil
	if not v or not v.root then return end
	local root = v.root
	local st = SS.parseState(v.model:GetAttribute("VesselState")) or {hp = 1, max = 1, trim = 0.5, cap = 0, crew = 1, policy = "open"}
	local look = root.CFrame.LookVector
	local point, deg = SS.compass(look.X, look.Z)
	local vel = root.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local wind, wx, wz, weather = windAt(root.Position)
	local rel = SS.relWind(look.X, look.Z, wx, wz)
	title.Text = string.upper(tostring(v.model:GetAttribute("VesselHull") or "ship")) .. "  ·  " .. string.upper(role or "")
	needle.Rotation = deg
	-- The arrow points where the wind blows, relative to the screen-north dial.
	windArrow.Rotation = (math.deg(math.atan2(wx, -wz)) + 360) % 360
	readout.Text = string.format("%s %03d°   ·   %d kn   ·   %d%% of top", point, deg, SS.knots(speed), math.floor(100 * speed / math.max(1, st.cap)))
	windText.Text = string.format("Wind %.1f %s · %s · best trim %d%%", wind, (if rel < SS.IRONS then "(in irons!)" else ""), weather, math.floor(SS.bestTrim(rel) * 100))
	local frac = math.clamp(st.hp / st.max, 0, 1)
	hullFill.Size = UDim2.fromScale(frac, 1)
	hullFill.BackgroundColor3 = if frac > 0.5 then T.color.defense elseif frac > 0.25 then T.color.gold else T.color.ember
	hullText.Text = string.format("HULL %d / %d", st.hp, st.max)
	trimText.Text = string.format("Sails trimmed %d%%   [ ]", math.floor(st.trim * 100))
	local canTrim = role == "helm" or string.sub(role or "", 1, 5) == "sails"
	trimDown.Visible, trimUp.Visible = canTrim, canTrim
	local s = tbl(S.state)
	local c = s.contract
	contractText.Text = if c then string.format("Cargo: %d crates → %s · %ds", c.crates, SS.PortById[SS.RouteById[c.route].to].name, c.left)
		.. (if c.loaded then "" else " (load at the origin)") else ""
	local gunner = string.sub(role or "", 1, 6) == "cannon"
	local sailing = tbl(s.sailing)
	fireB.Visible = gunner or (role == "helm" and sailing.cannon == true)
	local slow = speed <= SS.SLOW
	salvageB.Visible = slow and near("wreck", root.Position, SS.SALVAGE_RANGE) ~= nil
	fishB.Visible = slow and near("reef", root.Position, SS.FISH_RANGE) ~= nil
	local port, d = SS.nearestPort({x = root.Position.X, z = root.Position.Z})
	local atBerth = port and d <= SS.DOCK_RANGE or root.Position.Z > 2000
	dockB.Visible = role == "helm" and atBerth
	leaveB.Visible = role ~= "helm" and atBerth
end)
snapshots.Event:Connect(function(state)
	if type(state) == "table" and type(state.skysailing) == "table" then S.state = state.skysailing end
end)
send("snapshot")
