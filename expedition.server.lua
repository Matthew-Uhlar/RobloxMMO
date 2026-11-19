-- One shared expedition per server. Joining players can help an encounter in progress.
local Players = game:GetService("Players")
local Storage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local CollectionService=game:GetService("CollectionService")
local origin = Vector3.new(0, 42, 1800)
local dark = Color3.fromRGB(37, 52, 71)
local gold = Color3.fromRGB(255, 193, 94)
local teal = Color3.fromRGB(66, 223, 205)
local arena = Instance.new("Model")
arena.Name = "The Hollow Observatory"
arena.Parent = workspace

local function block(name, offset, size, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = origin + offset
	p.Color = color
	p.Material = material
	p.Parent = arena
	return p
end
local function artwork(anchor,shape,scale)
	anchor.Transparency=1
	anchor:SetAttribute("Shape",shape)
	anchor:SetAttribute("SculptureScale",scale)
	anchor:SetAttribute("VisualState","Active")
	CollectionService:AddTag(anchor,"AetherSculpture")
end

local function prompt(part, title, action, callback, distance)
	local p = Instance.new("ProximityPrompt")
	p.ObjectText = title
	p.ActionText = action
	p.HoldDuration = 0.35
	p.MaxActivationDistance = distance or 10
	p.RequiresLineOfSight = false
	p.Parent = part
	p.Triggered:Connect(function(player)
		local c = player.Character
		local root = c and c:FindFirstChild("HumanoidRootPart")
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 and (root.Position - part.Position).Magnitude <= p.MaxActivationDistance + 3 then
			callback(player, c)
		end
	end)
	return p
end

block("Observatory floor", Vector3.zero, Vector3.new(76, 3, 76), dark, Enum.Material.Slate)
for i = 0, 7 do
	local angle = math.pi * i / 4
	local offset = Vector3.new(math.cos(angle) * 33, 5, math.sin(angle) * 33)
	block("Ruined pier", offset, Vector3.new(4, 11, 4), dark, Enum.Material.Basalt)
	block("Beacon", offset + Vector3.yAxis * 6, Vector3.new(3, 1, 3), teal, Enum.Material.Neon)
end
local heart = block("Eclipse Heart", Vector3.new(0, 6, 0), Vector3.new(7, 7, 7), gold, Enum.Material.Neon)
heart.Shape = Enum.PartType.Ball
artwork(heart,"EclipseAstrolabe",1.25)
local label = Instance.new("BillboardGui")
label.Size = UDim2.fromOffset(320, 60)
label.StudsOffset = Vector3.new(0, 7, 0)
label.MaxDistance = 105
label.Parent = heart
local caption = Instance.new("TextLabel")
caption.Size = UDim2.fromScale(1, 1)
caption.BackgroundColor3 = dark
caption.BackgroundTransparency = 0.12
caption.Font = Enum.Font.GothamBold
caption.TextColor3 = Color3.new(1, 1, 1)
caption.TextSize = 17
caption.Parent = label
local members, pylons, charged = {}, {}, {}
local roles = {}
local remaining, health, pulse = 3, 12, 0
local guardians = {}
local guardianHealth = {6, 6}
local function guardsAlive()
	return guardianHealth[1] > 0 or guardianHealth[2] > 0
end
block("Sentinel hall floor", Vector3.new(0, 0, -110), Vector3.new(60, 3, 60), dark, Enum.Material.Slate)
for _, x in ipairs({-29,29}) do
	block("Sentinel hall wall", Vector3.new(x, 7, -110), Vector3.new(2, 14, 60), dark, Enum.Material.Basalt)
end
local passage = block("Sentinel passage", Vector3.new(0, 3, -26), Vector3.new(5, 5, 3), teal, Enum.Material.Glass)
local returnPassage = block("Core passage", Vector3.new(0, 3, -135), Vector3.new(5, 5, 3), gold, Enum.Material.Glass)
prompt(passage, "Sentinel hall", "Enter guardian chamber", function(player, character)
	if members[player] and remaining == 0 then character:PivotTo(CFrame.new(origin + Vector3.new(0,5,-87))) end
end)
prompt(returnPassage, "Observatory core", "Return to core", function(player, character)
	if members[player] and not guardsAlive() then character:PivotTo(CFrame.new(origin + Vector3.new(0,5,-22))) end
end)
local warning = block("Pulse radius", Vector3.new(0, 1.6, 0), Vector3.new(0.12, 27, 27), gold, Enum.Material.Neon)
warning.Shape = Enum.PartType.Cylinder
warning.Orientation = Vector3.new(0, 0, 90)
warning.CanCollide = false
warning.Transparency = 1

local function display()
	heart:SetAttribute("VisualState",if remaining>0 or guardsAlive() then "Shielded" elseif pulse>=3.5 then "Warning" else "Active")
	caption.Text = if remaining > 0 then "HOLLOW OBSERVATORY\nTune the prisms  •  " .. (3 - remaining) .. " / 3"
		elseif guardsAlive() then "SENTINEL HALL\nEnter the northern passage • defeat both guardians"
		else "ECLIPSE HEART  •  " .. health .. " / 12\nStep outside the amber pulse"
end
local function reset()
	table.clear(charged)
	remaining, health, pulse = 3, 12, 0
	guardianHealth = {6, 6}
	for _, guardian in guardians do guardian.Color = gold;guardian:SetAttribute("VisualState","Active") end
	warning.Transparency = 1
	for _, p in pylons do p.Color = teal;p:SetAttribute("VisualState","Active") end
	display()
end
for index, x in ipairs({-13,13}) do
	local guardian = block("Sentinel "..index, Vector3.new(x,5,-112), Vector3.new(5,8,5), gold, Enum.Material.Metal)
	artwork(guardian,"ObservatorySentinel",1.4)
	table.insert(guardians, guardian)
	prompt(guardian, "Sentinel • defeat to open the core passage", "Strike guardian", function(player, character)
		local member = members[player]
		if not member or remaining > 0 or guardianHealth[index] <= 0 or os.clock()-member.last < 0.8 then return end
		member.last = os.clock()
		member.contributed = true
		guardianHealth[index] = math.max(0, guardianHealth[index] - (if roles[player]=="Berserk" then 2 else 1))
		if guardianHealth[index] == 0 then guardian.Color = dark;guardian:SetAttribute("VisualState","Defeated") else
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			humanoid:TakeDamage(if roles[player]=="Tank" then 3 else 6)
		end
		display()
	end)
end
for i = 1, 3 do
	local a = i * math.pi * 2 / 3
	local p = block("Resonance prism", Vector3.new(math.cos(a)*22, 5, math.sin(a)*22), Vector3.new(3, 7, 3), teal, Enum.Material.Neon)
	p.Orientation = Vector3.new(0, i*45, 12)
	artwork(p,"AetherCrystal",1.3)
	table.insert(pylons, p)
	prompt(p, "Resonance prism", "Tune prism", function(player)
		if not members[player] or charged[i] then return end
		charged[i] = true
		members[player].contributed = true
		p.Color = gold
		p:SetAttribute("VisualState","Tuned")
		remaining -= 1
		display()
	end)
end
local gate
local function leave(player, character)
	members[player] = nil
	if character and gate and gate.Parent then
		character:PivotTo(gate.CFrame + Vector3.new(0, 5, 0))
	end
	if not next(members) then reset() end
end
local function strike(player, ranged)
	local member = members[player]
	local role = roles[player]
	if ranged and role ~= "Mage" and role ~= "Archer" then return end
	local recovery = if role == "Mage" then 2.4 elseif role == "Archer" then 1.2 else 0.8
	if not member or remaining > 0 or guardsAlive() or os.clock() - member.last < recovery then return end
	member.last = os.clock()
	member.contributed = true
	health -= if role == "Mage" then 3 elseif role == "Berserk" then 2 else 1
	if roles[player] == "Healer" then
		for ally in members do
			local character = ally.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and root and humanoid.Health > 0 and (root.Position-heart.Position).Magnitude <= 20 then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 3)
			end
		end
	end
	display()
	if health > 0 then return end
	local reward = Storage:FindFirstChild("IsleExpeditionReward")
	for participant, record in table.clone(members) do
		local character = participant.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if record.contributed and reward and root and humanoid and humanoid.Health > 0
			and (root.Position - origin).Magnitude <= 60 then
			reward:Fire(participant)
		end
		leave(participant, participant.Character)
	end
end
prompt(heart, "Eclipse Heart", "Strike core", function(player) strike(player, false) end)
local rangedPrompt = prompt(heart, "Mage / Archer", "Ranged attack", function(player) strike(player, true) end, 32)
rangedPrompt.KeyboardKeyCode = Enum.KeyCode.F
rangedPrompt.UIOffset = Vector2.new(0, 80)
local exit = block("Return arch", Vector3.new(0, 4, 29), Vector3.new(5, 5, 3), teal, Enum.Material.Glass)
prompt(exit, "Return arch", "Leave expedition", leave)
display()
RunService.Heartbeat:Connect(function(dt)
	if not next(members) or remaining > 0 or guardsAlive() then return end
	pulse += dt
	if pulse >= 5 then
		pulse = 0
		for player in members do
			local c = player.Character
			local root = c and c:FindFirstChild("HumanoidRootPart")
			local hum = c and c:FindFirstChildOfClass("Humanoid")
			if hum and root and (root.Position - heart.Position).Magnitude <= 13.5 then
				local damage = if roles[player] == "Tank" then 9 else 18
				local defense = math.clamp(player:GetAttribute("SkillDefense") or 0, 0, 5)
				hum:TakeDamage(math.max(1, damage - defense))
			end
		end
	end
	warning.Transparency = if pulse >= 3.5 then 0.25 else 1
	heart:SetAttribute("VisualState",if pulse>=3.5 then "Warning" else "Active")
end)
local function watch(player)
	player.CharacterRemoving:Connect(function() leave(player) end)
end
Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do watch(player) end
Players.PlayerRemoving:Connect(function(player) leave(player); roles[player] = nil end)
local function attach(part)
	if gate or part.Name ~= "ExpeditionGate" or not part:IsA("BasePart") then return end
	gate = part
	for index, role in ipairs({"Berserk", "Healer", "Tank", "Mage", "Archer"}) do
		local pedestal = block(role .. " oath", Vector3.zero, Vector3.new(2, 3, 2), teal, Enum.Material.Slate)
		pedestal.Position = part.Position + Vector3.new((index-3)*4, 0, 7)
		local description = ({Berserk="Double core damage", Healer="Strikes heal nearby allies", Tank="Half pulse damage",
			Mage="Slow ranged burst", Archer="Quick ranged shots"})[role]
		prompt(pedestal, role .. " • " .. description, "Choose role", function(player)
			if members[player] then return end
			roles[player] = role
			player:SetAttribute("ExpeditionRole", role)
		end)
	end
	prompt(part, "Hollow Observatory", "Enter expedition", function(player, c)
		members[player] = members[player] or {last = 0}
		c:PivotTo(CFrame.new(origin + Vector3.new(0, 5, 24)))
	end)
end
workspace.DescendantAdded:Connect(attach)
for _, part in workspace:GetDescendants() do attach(part) end
