-- Island Assembly festival notice board (Events team).
-- * Publishes the Skyward Calendar (Data.calendarAt(os.time()), identical on every
--   server) as workspace attributes: AetherYear, AetherSeason, AetherDay,
--   AetherEvent, AetherEventEnds, AetherEventKey (nil outside events), AetherNextEvent,
--   AetherNextEventStarts. Server hooks honour them only while they match the calendar.
-- * Runs the server-local harvest ballot that sets FestivalResource (+1 yield).
--   During the Bloomtide Fair the ballot chooses the fair's featured crop instead
--   (that crop yields double for the rest of the fair; see Data.eventGather).
-- * Hosts the Festival Vendor stall (IsleAction "eventVendor"; trades are verified
--   by server.server.lua through Data.eventAction).
local Players = game:GetService("Players")
local ballots = {}
local choices = {"Timber", "Ore", "Herb", "Fish"}
-- Shared calendar rules. Without them (e.g. a stripped test place) the board
-- still runs the classic ballot.
local okData, Data = pcall(function()
	return require(game:GetService("ReplicatedStorage"):WaitForChild("AetherData"))
end)
if not okData or type(Data) ~= "table" or type(Data.calendarAt) ~= "function" then Data = nil end
local crops = {}
if Data then for _, r in ipairs(Data.ResourceTiers.Farming) do table.insert(crops, r.id) end end

-- Board pieces (nil until the ExpeditionGate exists). The calendar itself is
-- published every second from the start, board or not, so a missing or late
-- gate never switches the Skyward Calendar (and its events) off.
local board, date, eventLine, title
local buttons = {}
local function placeBoard(gate)
	if board then return end
	local ink, gold, ivory, mint = Color3.fromRGB(26, 51, 60), Color3.fromRGB(255, 220, 150), Color3.fromRGB(255, 244, 217), Color3.fromRGB(158, 231, 210)
	-- §28 (QC M2): no post; an invisible anchor carries a floating, camera-
	-- facing notice (readable from any side of the expedition arch). It is
	-- sized in studs (like the old 9 x 5.5 board), so it scales like an object.
	board = Instance.new("Part")
	board.Name = "Island Assembly"
	board.Size = Vector3.new(1, 1, 1)
	board.Anchored = true
	board.CanCollide = false
	board.CanTouch = false
	board.CanQuery = false
	board.CastShadow = false
	board.Transparency = 1
	board.CFrame = gate.CFrame + Vector3.new(16, 2.25, 8)
	board:SetAttribute("NoticeAnchor", true)
	board.Parent = workspace
	local sign = Instance.new("BillboardGui")
	sign.Name = "NoticeBillboard"
	sign.Size = UDim2.fromScale(9, 5.5)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 1.2, 0)
	sign.MaxDistance = 90
	sign.AlwaysOnTop = false
	sign.LightInfluence = 0.15
	sign.Brightness = 1.25
	sign.Parent = board
	local headerFont = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)
	local bodyFont = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
	-- Lines laid out in fractions of the board; TextScaled with a size cap so
	-- the text follows the board's on-screen size.
	local function line(name, y, height, size, color, font)
		local text = Instance.new("TextLabel")
		text.Name = name
		text.BackgroundTransparency = 1
		text.TextColor3 = color
		text.FontFace = font or bodyFont
		text.TextScaled = true
		text.TextWrapped = true
		text.RichText = true
		text.Position = UDim2.new(0.04, 0, y / 440, 0)
		text.Size = UDim2.new(0.92, 0, height / 440, 0)
		text.ZIndex = 3
		local cap = Instance.new("UITextSizeConstraint")
		cap.MaxTextSize = size
		cap.Parent = text
		local outline = Instance.new("UIStroke")
		outline.Color = Color3.fromRGB(5, 7, 10)
		outline.Thickness = 1
		outline.Transparency = 0.4
		outline.Parent = text
		text.Parent = sign
		return text
	end
	-- Notice styling (the sign family's metal frame, field and trim).
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.BackgroundColor3 = gold
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 1
	backdrop.Parent = sign
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.04, 0)
	corner.Parent = backdrop
	local field = Instance.new("Frame")
	field.Name = "Field"
	field.BackgroundColor3 = ink
	field.BorderSizePixel = 0
	field.Position = UDim2.fromScale(0.015, 0.025)
	field.Size = UDim2.fromScale(0.97, 0.95)
	field.ZIndex = 2
	field.Parent = sign
	local trim = Instance.new("UIStroke")
	trim.Color = mint
	trim.Thickness = 1.5
	trim.Transparency = 0.3
	trim.Parent = field
	local header = line("Header", 8, 40, 30, gold, headerFont)
	date = line("Date", 50, 64, 22, ivory)
	eventLine = line("Event", 118, 150, 26, mint)
	title = line("Ballot", 276, 156, 26, gold)
	header.Text = "ISLAND ASSEMBLY  •  SKYWARD CALENDAR"
	for i, name in {"A", "B"} do
		local anchor = Instance.new("Attachment")
		anchor.Position = Vector3.new((i-1.5)*3, -1.5, 0)
		anchor.Parent = board
		local p = Instance.new("ProximityPrompt")
		p.Name = "Vote" .. name
		p.RequiresLineOfSight = false
		p.ObjectText = "Island Assembly"
		p.KeyboardKeyCode = if i == 1 then Enum.KeyCode.E else Enum.KeyCode.F
		p.UIOffset = Vector2.new(0, (i-1.5)*78)
		p.Parent = anchor
		buttons[i] = p
		p.Triggered:Connect(function(player)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if p.Enabled and root and (root.Position-board.CFrame.Position).Magnitude <= 13 then
				ballots[player] = i
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(player) ballots[player] = nil end)
	-- Festival Vendor stall beside the board (server.server.lua answers the prompt).
	local stall = Instance.new("Part")
	stall.Name = "Festival Vendor"
	stall.Size = Vector3.new(4, 3, 2.5)
	stall.Anchored = true
	stall.Material = Enum.Material.WoodPlanks
	stall.Color = Color3.fromRGB(150, 92, 60)
	stall.CFrame = board.CFrame + Vector3.new(8, -2.4, 0)
	stall.Parent = workspace
	local awning = Instance.new("Part")
	awning.Name = "Vendor Awning"
	awning.Size = Vector3.new(4.6, 0.3, 3)
	awning.Anchored = true
	awning.CanCollide = false
	awning.Material = Enum.Material.Fabric
	awning.Color = Color3.fromRGB(199, 125, 255)
	awning.CFrame = stall.CFrame + Vector3.new(0, 3.2, 0)
	awning.Parent = workspace
	local vendor = Instance.new("ProximityPrompt")
	vendor.Name = "VendorPrompt"
	vendor.ActionText = "Trade"
	vendor.ObjectText = "Festival Vendor"
	vendor.RequiresLineOfSight = false
	vendor.MaxActivationDistance = 10
	vendor:SetAttribute("IsleAction", "eventVendor")
	vendor:SetAttribute("IsleItem", "Vendor")
	vendor.Parent = stall
end
local gate = workspace:FindFirstChild("ExpeditionGate", true)
if gate and gate:IsA("BasePart") then placeBoard(gate) else
	workspace.DescendantAdded:Connect(function(obj)
		if not board and obj.Name == "ExpeditionGate" and obj:IsA("BasePart") then placeBoard(obj) end
	end)
end

local function span(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 86400 then return string.format("%dd %dh", seconds // 86400, seconds % 86400 // 3600) end
	if seconds >= 3600 then return string.format("%dh %02dm", seconds // 3600, seconds % 3600 // 60) end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end
local function itemName(id) return Data and Data.Items[id] and Data.Items[id].name or id end
-- Publishes the date every tick and returns the calendar (nil without Data).
local function publish(now)
	if not Data then return nil end
	local cal = Data.calendarAt(now)
	local nextEvent = Data.upcomingEvents(now, 2)
	local upcoming = if cal.event then nextEvent[2] else nextEvent[1]
	workspace:SetAttribute("AetherYear", cal.year)
	workspace:SetAttribute("AetherSeason", cal.season)
	workspace:SetAttribute("AetherDay", cal.day)
	workspace:SetAttribute("AetherEvent", cal.event)
	workspace:SetAttribute("AetherEventEnds", cal.eventEnds)
	workspace:SetAttribute("AetherEventKey", cal.eventKey)
	workspace:SetAttribute("AetherNextEvent", upcoming.id)
	workspace:SetAttribute("AetherNextEventStarts", upcoming.starts)
	if not date then return cal end
	local season = Data.SeasonById[cal.season]
	date.Text = string.format("Year %d  •  <b>%s %d</b> of %d  •  dusk in %s\n%s", cal.year, season.name, cal.day,
		Data.Calendar.daysPerSeason, span(cal.dayEnds - now), season.text)
	if cal.event then
		local ev = Data.Events[cal.event]
		eventLine.Text = string.format("NOW: %s  •  %s left\n<font size=\"20\">%s</font>", string.upper(ev.name), span(cal.eventEnds - now), ev.text)
	else
		eventLine.Text = string.format("NEXT: %s in %s\n<font size=\"20\">%s</font>", Data.Events[upcoming.id].name, span(upcoming.starts - now), Data.Events[upcoming.id].text)
	end
	return cal
end
-- Ballot options: crops while the Bloomtide Fair runs, otherwise the classic four.
local function ballotOptions(cal, round)
	local list = if cal and cal.event == "BloomtideFair" and #crops >= 2 then crops else choices
	return {list[round % #list + 1], list[(round + 1) % #list + 1]}, list == crops
end

local round = 0
local now = os.time()
-- Until the board exists only the calendar runs (the ballot needs the board).
while not board do
	publish(os.time())
	task.wait(1)
end
while true do
	table.clear(ballots)
	workspace:SetAttribute("FestivalResource", nil)
	local options, fair = ballotOptions(publish(os.time()), round)
	for i,p in buttons do p.ActionText = "Vote " .. itemName(options[i]); p.Enabled = true end
	local counts = {0,0}
	for seconds = 45, 0, -1 do
		now = os.time()
		publish(now)
		counts = {0,0}
		for _,vote in ballots do counts[vote] += 1 end
		title.Text = string.format("%s   •   %ds\n%s  %d     /     %s  %d", if fair then "FEATURED CROP VOTE" else "HARVEST BALLOT", seconds,
			itemName(options[1]), counts[1], itemName(options[2]), counts[2])
		task.wait(1)
	end
	for _,p in buttons do p.Enabled = false end
	local winner = options[if counts[2] > counts[1] then 2 else 1]
	workspace:SetAttribute("FestivalResource", winner)
	for seconds = 180, 1, -1 do
		now = os.time()
		local cal = publish(now)
		local featured = fair and cal and cal.event == "BloomtideFair"
		title.Text = string.format("%s   •   %d:%02d\n+1 %s per harvest%s", if featured then "FEATURED CROP" else "HARVEST FESTIVAL",
			math.floor(seconds/60), seconds%60, itemName(winner), if featured then "  •  double yield at the Fair" else "")
		task.wait(1)
	end
	round += 1
end
