-- Short server-local ballots let a group choose a gathering bonus together.
local Players = game:GetService("Players")
local ballots = {}
local choices = {"Timber", "Ore", "Herb", "Fish"}
local gate = workspace:FindFirstChild("ExpeditionGate", true)
while not gate do
	local obj = workspace.DescendantAdded:Wait()
	if obj.Name == "ExpeditionGate" and obj:IsA("BasePart") then gate = obj end
end
local board = Instance.new("Part")
board.Name = "Island Assembly"
board.Size = Vector3.new(6, 3, 1)
board.Anchored = true
board.Material = Enum.Material.Slate
board.Color = Color3.fromRGB(26, 51, 60)
board.CFrame = gate.CFrame + Vector3.new(16, 1, 8)
board.Parent = workspace
-- A fixed physical face cannot follow the camera across the expedition arch.
local sign = Instance.new("SurfaceGui")
sign.Face=Enum.NormalId.Back
sign.CanvasSize=Vector2.new(480,240)
sign.AlwaysOnTop=false
sign.LightInfluence=0
sign.Parent = board
local title = Instance.new("TextLabel")
title.BackgroundColor3 = board.Color
title.TextColor3 = Color3.fromRGB(255, 220, 150)
title.Font = Enum.Font.GothamBold
title.TextSize = 28
title.TextWrapped=true
title.Size = UDim2.fromScale(1, 1)
title.Parent = sign
local buttons = {}
for i, name in {"A", "B"} do
	local anchor = Instance.new("Attachment")
	anchor.Position = Vector3.new((i-1.5)*3, 1, 0)
	anchor.Parent = board
	local p = Instance.new("ProximityPrompt")
	p.RequiresLineOfSight = false
	p.ObjectText = "Island Assembly"
	p.KeyboardKeyCode = if i == 1 then Enum.KeyCode.E else Enum.KeyCode.F
	p.UIOffset = Vector2.new(0, (i-1.5)*78)
	p.Parent = anchor
	buttons[i] = p
	p.Triggered:Connect(function(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if p.Enabled and root and (root.Position-board.Position).Magnitude <= 13 then
			ballots[player] = i
		end
	end)
end
Players.PlayerRemoving:Connect(function(player) ballots[player] = nil end)
local round = 0
while true do
	table.clear(ballots)
	workspace:SetAttribute("FestivalResource", nil)
	local options = {choices[round%4 + 1], choices[(round+1)%4 + 1]}
	for i,p in buttons do p.ActionText = "Vote " .. options[i]; p.Enabled = true end
	local counts = {0,0}
	for seconds = 45, 0, -1 do
		counts = {0,0}
		for _,vote in ballots do counts[vote] += 1 end
		title.Text = string.format("ISLAND ASSEMBLY   •   %ds\n%s  %d     /     %s  %d", seconds, options[1], counts[1], options[2], counts[2])
		task.wait(1)
	end
	for _,p in buttons do p.Enabled = false end
	local winner = options[if counts[2] > counts[1] then 2 else 1]
	workspace:SetAttribute("FestivalResource", winner)
	for seconds = 180, 1, -1 do
		title.Text = string.format("HARVEST FESTIVAL   •   %d:%02d\n+1 %s per harvest", math.floor(seconds/60), seconds%60, winner)
		task.wait(1)
	end
	round += 1
end
