-- Isle HUD (StarterPlayerScripts.IsleHud): the OSRS-style satchel side panel
-- (28-slot grid, bag pages, search, sort, drag-and-drop, context menu, examine,
-- rarity lore tooltips), the equipment paperdoll with its stat sheet, OSRS-style
-- XP drops and the skill progress toast, and the Sky Chart (warp map).
-- See docs/DEPTH-CONTRACT.md §29.
--
-- Data: every snapshot the atlas accepts (ReplicatedStorage.IsleSnapshotLocal)
-- plus IsleUpdate pushes. Actions go through the atlas (IsleActionLocal:Fire(
-- verb, item)), which owns the IsleAction round trip, so there is one pending
-- request at a time and every reply refreshes every HUD:
--   Wield / Equip   equip "<id>"        Unequip   unequip "<slot>"
--   Eat / Drink     consume "<id>"      Equip (accessory) accessory "<id>"
--   Use (pet item)  petAdopt "<id>"     Sell      sell "<id>"
--   Drop            drop "<id>"         reorder   satchelMove "<id>:<index>"
--   Sort            satchelSort "<mode>"   Sky Chart: recall "Hub" | "Home"
-- Move to hotbar calls ReplicatedStorage.HotbarApi:Invoke("assign", slot, id)
-- (hotbar.client.lua); region warps set a Wayfinder waypoint to the beacon.
-- Opened by: E / Tab, the sidebar's Satchel button and IsleHudLocal:Fire("satchel");
-- M (or the MAP dock button) opens the Sky Chart. Tab belongs to the satchel, so
-- Roblox's player list (also on Tab) is turned off here.
-- Local attributes published: IsleSatchelOpen (docked on desktop and tablets;
-- the right column HUDs step left of it).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Input = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer

local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local T = require(ReplicatedStorage:WaitForChild("AetherUiTheme"))
local C, make = T.color, T.make

local function channel(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then return existing end
	local created = Instance.new("BindableEvent")
	created.Name = name
	created.Parent = ReplicatedStorage
	return created
end
local actions, toasts = channel("IsleActionLocal"), channel("IsleToastLocal")
local hudEvents, xpEvents = channel("IsleHudLocal"), channel("IsleXpLocal")

local gui = make("ScreenGui", player:WaitForChild("PlayerGui"), {Name = "IsleHud", ResetOnSpawn = false, DisplayOrder = 9,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling})

local S = {snap = nil, items = {}, order = {}, page = 1, search = "", sort = "rarity", view = "Items", open = false, pinned = false,
	selected = nil, confirm = nil, drag = nil, menuFor = nil, slots = {}, doll = {}, menuButtons = {}}
local PER_PAGE = 28 -- pooled slots; S.perPage shrinks on short desktop windows (fewer rows, more pages)
S.perPage = PER_PAGE
-- Shown ProximityPrompts (E is their key): a set keyed by prompt, pruned of
-- prompts that were destroyed without a PromptHidden.
S.prompts = {}
pcall(function()
	local prompts = game:GetService("ProximityPromptService")
	prompts.PromptShown:Connect(function(prompt) if prompt then S.prompts[prompt] = true end end)
	prompts.PromptHidden:Connect(function(prompt) if prompt then S.prompts[prompt] = nil end end)
end)
function S.promptShowing()
	for prompt in pairs(S.prompts) do
		local ok, parent = pcall(function() return prompt.Parent end)
		if not ok or parent == nil then S.prompts[prompt] = nil else return true end
	end
	return false
end
-- Tab is the satchel's key: Roblox's player list (also on Tab) stays off.
pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false) end)
local function tbl(v) return if type(v) == "table" then v else {} end
local function screen()
	local size = gui.AbsoluteSize
	if size and size.X > 0 and size.Y > 0 then return size end
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1366, 768)
end
local function layout() return T.hudLayout(screen().X, screen().Y, {touch = Input.TouchEnabled, satchelOpen = S.open and S.docked}) end
-- The satchel docks on any screen tall enough (desktop and tablets alike); only
-- short screens (phones) get the modal. Screen size decides, not TouchEnabled.
local function dockable() return not T.hudLayout(screen().X, screen().Y, {touch = Input.TouchEnabled}).short end
local function toast(text) if text then toasts:Fire(text) end end
local function send(verb, item) actions:Fire(verb, item) end
local function depth() return tbl(S.snap and S.snap.depth) end
local function equippedSlot(id)
	for slot, eid in pairs(tbl(depth().equipment)) do if eid == id then return slot end end
	return nil
end
local function bagged(id) return table.find(tbl(depth().accessoryBag), id) ~= nil end
local function levels() return tbl(S.snap and S.snap.levels) end

------------------------------------------------------------------------------
-- Satchel panel
------------------------------------------------------------------------------
-- Phones: the satchel is a modal over a dimmed screen (tap outside to close).
local satchelShade = make("TextButton", gui, {Name = "SatchelShade", Text = "", AutoButtonColor = false, BackgroundColor3 = C.void, BackgroundTransparency = 0.45,
	BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 1, Selectable = false})
local panel = T.frame(gui, {name = "Satchel", title = "SATCHEL", size = UDim2.fromOffset(226, 420), visible = false, zIndex = 2})
local body = panel:FindFirstChild("Body")
local close = T.button(panel, "✕", {name = "CloseSatchel", size = UDim2.fromOffset(26, 22), anchor = Vector2.new(1, 0), position = UDim2.new(1, -6, 0, 4), tone = "ghost", textSize = 13})
local pin = T.button(panel, "Pin", {name = "PinSatchel", size = UDim2.fromOffset(40, 22), anchor = Vector2.new(1, 0), position = UDim2.new(1, -36, 0, 4), tone = "ghost", textSize = 11})
local tabs = T.tabs(body, {"Items", "Gear"}, "Items", function(name) S.view = name; S.refresh() end, {name = "SatchelTabs", position = UDim2.fromOffset(8, 6), size = UDim2.new(1, -16, 0, 30)})
-- Items view
local itemsView = make("Frame", body, {Name = "ItemsView", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40)})
local search = make("TextBox", itemsView, {Name = "Search", PlaceholderText = "Search…", Text = "", ClearTextOnFocus = false, Font = T.font.body, TextSize = 13,
	TextColor3 = C.text, PlaceholderColor3 = C.faint, BackgroundColor3 = C.void, BackgroundTransparency = 0.2, BorderSizePixel = 0,
	Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -96, 0, 28), TextXAlignment = Enum.TextXAlignment.Left})
T.corner(search, 4)
make("UIStroke", search, {Color = C.line, Thickness = 1})
make("UIPadding", search, {PaddingLeft = UDim.new(0, 8)})
local sortButton = T.button(itemsView, "Rarity", {name = "SortButton", size = UDim2.fromOffset(80, 28), anchor = Vector2.new(1, 0), position = UDim2.new(1, -8, 0, 0), textSize = 11})
local grid = make("Frame", itemsView, {Name = "Grid", BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 34), Size = UDim2.new(1, -16, 1, -70)})
local footer = make("Frame", itemsView, {Name = "Pager", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -4), Size = UDim2.new(1, -16, 0, 28)})
local prevPage = T.button(footer, "‹", {name = "PrevPage", size = UDim2.fromOffset(28, 28), textSize = 16})
local nextPage = T.button(footer, "›", {name = "NextPage", size = UDim2.fromOffset(28, 28), anchor = Vector2.new(1, 0), position = UDim2.fromScale(1, 0), textSize = 16})
local pageLabel = T.label(footer, {Name = "PageLabel", Position = UDim2.fromOffset(32, 0), Size = UDim2.new(1, -64, 1, 0), TextXAlignment = Enum.TextXAlignment.Center,
	Font = T.font.label, TextSize = 11, TextColor3 = C.dim, RichText = true})
-- Gear view (paperdoll + stat sheet)
local gearView = make("Frame", body, {Name = "GearView", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), Visible = false})
local doll = make("Frame", gearView, {Name = "Paperdoll", BackgroundColor3 = C.void, BackgroundTransparency = 0.45, BorderSizePixel = 0, Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 0, 204)})
T.corner(doll, 5)
make("UIStroke", doll, {Color = C.line, Thickness = 1})
-- Silhouette spine behind the centre column (head, body, legs, feet).
local figure = make("Frame", doll, {Name = "Figure", AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = C.raised, BackgroundTransparency = 0.6, BorderSizePixel = 0})
T.corner(figure, 8)
-- OSRS equipment layout on a 3 × 4 grid: bag · head · pet / weapon · body ·
-- quiver / legs / feet (col, row). The shortest phones lay the slots in a row.
local DOLL = {
	{slot = "accessory", label = "Bag", col = 1, row = 1}, {slot = "helmet", label = "Head", col = 2, row = 1}, {slot = "pet", label = "Pet", col = 3, row = 1},
	{slot = "weapon", label = "Weapon", col = 1, row = 2}, {slot = "chest", label = "Body", col = 2, row = 2}, {slot = "ammo", label = "Quiver", col = 3, row = 2},
	{slot = "legs", label = "Legs", col = 2, row = 3}, {slot = "boots", label = "Feet", col = 2, row = 4},
}
for _, d in ipairs(DOLL) do
	local b = T.slot(doll, {name = "Equip" .. d.slot, size = 40})
	b.AnchorPoint = Vector2.new(0.5, 0)
	T.label(b, {Name = "SlotName", Text = d.label, Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 10), TextSize = 8, Font = T.font.label,
		TextColor3 = C.faint, TextXAlignment = Enum.TextXAlignment.Center, Visible = false})
	S.doll[d.slot] = b
end
local statsList = make("ScrollingFrame", gearView, {Name = "StatSheet", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(8, 210),
	Size = UDim2.new(1, -16, 1, -214), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3, ScrollBarImageColor3 = C.frame})
make("UIListLayout", statsList, {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1)})
local STAT_SHEET = {"health", "defense", "strength", "critChance", "critDamage", "speed", "intelligence", "attackSpeed", "magicFind", "miningFortune", "petLuck"}
local statRows = {}
for i, key in ipairs(STAT_SHEET) do
	local def = Data.Stats[key]
	local row = make("Frame", statsList, {Name = "Stat_" .. key, LayoutOrder = i, BackgroundColor3 = C.void, BackgroundTransparency = if i % 2 == 0 then 0.7 else 1,
		BorderSizePixel = 0, Size = UDim2.new(1, -4, 0, 17)})
	T.label(row, {Name = "Name", Text = def.symbol .. " " .. def.name, Position = UDim2.fromOffset(4, 0), Size = UDim2.new(0.66, 0, 1, 0), TextSize = 12,
		TextColor3 = T.rgb(def.color), Font = T.font.label})
	statRows[key] = T.label(row, {Name = "Value", Text = "—", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 0), Size = UDim2.new(0.34, 0, 1, 0),
		TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Font = T.font.label})
end
-- Pooled grid slots (4 × 7).
for i = 1, PER_PAGE do
	local b = T.slot(grid, {name = "Slot" .. i, size = 44})
	S.slots[i] = b
end
-- Shared overlays: tooltip, context menu, drag ghost.
local tooltip = T.tooltip(gui)
local menu = T.frame(gui, {name = "ContextMenu", size = UDim2.fromOffset(170, 40), ornate = false, rimThickness = 1.5, visible = false, zIndex = 40, transparency = 0.02})
local menuTitle = T.label(menu, {Name = "MenuTitle", Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 18), Font = T.font.label, TextSize = 12, ZIndex = 41, RichText = true})
local menuList = make("Frame", menu, {Name = "Options", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 24), Size = UDim2.new(1, -8, 1, -28), ZIndex = 41})
make("UIListLayout", menuList, {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2)})
local ghost = T.slot(gui, {name = "DragGhost", size = 44})
ghost.Visible, ghost.ZIndex, ghost.Active = false, 60, false

------------------------------------------------------------------------------
-- Inventory model
------------------------------------------------------------------------------
-- Owned ids in the player's satchel order (server `satchel` list first, any
-- other owned ids after it by rarity), filtered by the search text.
local function ownedIds()
	local items = tbl(S.snap and S.snap.items)
	local seen, ids = {}, {}
	for _, id in ipairs(tbl(S.snap and S.snap.satchel)) do
		if type(id) == "string" and not seen[id] and (tonumber(items[id]) or 0) > 0 and Data.Items[id] then seen[id] = true; table.insert(ids, id) end
	end
	local rest = {}
	for id, n in pairs(items) do
		if not seen[id] and (tonumber(n) or 0) > 0 and Data.Items[id] then table.insert(rest, id) end
	end
	T.sortItems(rest, Data.Items, S.sort)
	for _, id in ipairs(rest) do table.insert(ids, id) end
	return ids
end
local function visibleIds()
	local all = ownedIds()
	S.all = all
	if S.search == "" then return all end
	local needle, out = string.lower(S.search), {}
	for _, id in ipairs(all) do
		local def = Data.Items[id]
		if string.find(string.lower(def.name or id), needle, 1, true) or string.find(string.lower(T.kindLabel(def)), needle, 1, true) then table.insert(out, id) end
	end
	return out
end
function S.ctx(id)
	local def = Data.Items[id]
	local gear = tbl(depth().gear)
	local enchants = tbl(depth().enchants)[id]
	-- Upgrades bound to the id (server Gear.upgraded): reforge, stars, master stars, tome, enchantments.
	local upgraded = tbl(gear.reforges)[id] ~= nil or (tonumber(tbl(gear.stars)[id]) or 0) > 0 or (tonumber(tbl(gear.masterStars)[id]) or 0) > 0
		or tbl(gear.books)[id] ~= nil or (type(enchants) == "table" and next(enchants) ~= nil)
	return {Data = Data, count = tonumber(tbl(S.snap and S.snap.items)[id]) or 0, equipped = equippedSlot(id) ~= nil, bagged = bagged(id),
		levels = levels(), enchants = enchants, upgraded = upgraded}, def
end

------------------------------------------------------------------------------
-- Tooltip and context menu
------------------------------------------------------------------------------
local function showTip(id, at)
	local ctx, def = S.ctx(id)
	if not def then tooltip.Visible = false; return end
	T.showTooltip(tooltip, T.lore(def, ctx), at, screen())
end
local function hideMenu() menu.Visible = false; S.menuFor = nil; S.confirm = nil end
function S.run(option, id)
	local def = Data.Items[id]
	if option.confirm and S.confirm ~= option.id .. id then
		S.confirm = option.id .. id
		toast(option.label .. " " .. def.name .. "?" .. (if option.upgraded then " It carries upgrades: the upgraded copy is kept, only spares go." else "") .. " Choose it again to confirm.")
		return false
	end
	S.confirm = nil
	if option.verb then
		send(option.verb, option.arg)
	elseif option["local"] == "examine" then
		toast(T.examine(def))
	elseif option["local"] == "hotbar" then
		-- The first free slot of 3–9 (1–2 are the weapon / tool); never overwrite.
		local api = ReplicatedStorage:FindFirstChild("HotbarApi")
		local ok, done, message = false, false, nil
		if api then
			ok, done, message = pcall(function()
				local slots = api:Invoke("getSlots")
				local list = type(slots) == "table" and type(slots.slots) == "table" and slots.slots or nil
				if not list then return false, nil end
				for i = 3, 9 do if list[i] == id then return false, def.name .. " is already on your hotbar (slot " .. i .. ")." end end
				for i = 3, 9 do if not list[i] then return api:Invoke("assign", i, id) end end
				return false, "Your hotbar is full (slots 3–9). Clear a slot on the hotbar first."
			end)
		end
		toast(if ok and done then def.name .. " moved to your hotbar." elseif ok and message then message else "The hotbar is still being fitted. Try again in a moment.")
	elseif option["local"] == "use" then
		hudEvents:Fire("open", "Satchel", "Collections")
	end
	return true
end
local function openMenu(id, at)
	local ctx, def = S.ctx(id)
	if not def then return end
	S.menuFor = id
	local options = T.itemActions(def, ctx)
	local touch = Input.TouchEnabled
	local rowH = if touch then 44 else 26
	menuTitle.Text = "<font color=\"#" .. T.rarity(def.rarity).hex .. "\">" .. T.escape(def.name) .. "</font>"
	for i, option in ipairs(options) do
		local b = S.menuButtons[i]
		if not b then
			b = T.button(menuList, "", {name = "Option" .. i, order = i, textSize = 12, tone = "ghost"})
			b.ZIndex = 42
			b.TextXAlignment = Enum.TextXAlignment.Left
			make("UIPadding", b, {PaddingLeft = UDim.new(0, 8)})
			b.Activated:Connect(function()
				local o = b:GetAttribute("Option")
				local item = S.menuFor
				local current = item and T.itemActions(Data.Items[item], (S.ctx(item)))
				for _, candidate in ipairs(current or {}) do
					if candidate.id == o then
						if S.run(candidate, item) then hideMenu() end
						return
					end
				end
			end)
			S.menuButtons[i] = b
		end
		b.Visible = true
		b.Text = option.label
		b.Name = "Option" .. option.id
		b:SetAttribute("Option", option.id)
		b.Size = UDim2.new(1, 0, 0, rowH)
		T.tone(b, if option.danger then "danger" elseif i == 1 and option.verb then "primary" else "ghost")
	end
	for i = #options + 1, #S.menuButtons do S.menuButtons[i].Visible = false end
	local h = 28 + #options * (rowH + 2) + 4
	local view = screen()
	menu.Size = UDim2.fromOffset(if touch then 190 else 170, h)
	menu.Position = UDim2.fromOffset(math.clamp(at.X, 4, view.X - 194), math.clamp(at.Y, 4, math.max(4, view.Y - h - 4)))
	menu.Visible = true
	tooltip.Visible = false
end
S.openMenu = openMenu

------------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------------
local function placePanel()
	local L = layout()
	local touch = Input.TouchEnabled or L.short
	S.docked = not L.short
	local rect = L.satchel
	-- Grid shapes (28 slots a page): 7 × 4 on the docked panel and the phone
	-- modal, 14 × 2 on the shortest phones. A short desktop window first shrinks
	-- the cells (to the 34 px floor), then drops to fewer rows (more pages).
	local cols = if L.tiny then 14 elseif rect.w >= 300 then 7 else 4
	local rows = PER_PAGE // cols
	local tall = if touch then 44 else 28
	local toolbar = if touch then 4 + tall + 6 else 6 + 30 + 4 + tall + 6
	-- Touch: a taller header so the close button is a full 44 px target.
	local headerH = if touch then 46 else 28
	local band, bodyFrame = panel:FindFirstChild("Header"), panel:FindFirstChild("Body")
	band.Size = UDim2.new(1, -6, 0, headerH - 3)
	panel:FindFirstChild("HeaderRule").Position = UDim2.new(0, 10, 0, headerH)
	bodyFrame.Position, bodyFrame.Size = UDim2.fromOffset(0, headerH), UDim2.new(1, 0, 1, -headerH)
	local pager = tall + 8
	local cellMin = if touch then 44 else 34
	local cell = math.floor(math.min((rect.w - 16 - (cols - 1) * 4) / cols, 52))
	if not L.short then
		local room = rect.h - headerH - toolbar - pager
		cell = math.min(cell, math.floor(room / rows) - 4)
		if cell < cellMin then rows = math.clamp(math.floor(room / (cellMin + 4)), 1, rows) end
	end
	cell = math.max(cell, cellMin)
	S.perPage = rows * cols
	local width = math.max(rect.w, cols * (cell + 4) + 12)
	local height = math.min(if L.short then L.h - 8 else rect.h, headerH + toolbar + rows * (cell + 4) + pager)
	if L.short then
		width = math.min(width, L.w - 16)
		panel.Position = UDim2.fromOffset(math.floor((L.w - width) / 2), math.floor((L.h - height) / 2))
	else
		panel.Position = UDim2.fromOffset(rect.x + rect.w - width, rect.y)
	end
	panel.Size = UDim2.fromOffset(width, height)
	for i, b in ipairs(S.slots) do
		local c, r = (i - 1) % cols, (i - 1) // cols
		b.Size = UDim2.fromOffset(cell, cell)
		b.Position = UDim2.fromOffset(c * (cell + 4), r * (cell + 4))
		b.Visible = i <= S.perPage
	end
	S.cell, S.cols = cell, cols
	grid.Size = UDim2.new(1, -16, 0, rows * (cell + 4))
	close.Size = UDim2.fromOffset(if touch then 44 else 26, if touch then 44 else 22)
	close.Position = UDim2.new(1, -4, 0, if touch then 1 else 3)
	pin.Visible = S.docked
	local tabRow = tabs.Items.Parent
	if touch then
		-- One toolbar row: [Items|Gear] [search…] [sort].
		tabRow.Position, tabRow.Size = UDim2.fromOffset(8, 1), UDim2.fromOffset(156, tall + 6)
		for _, b in pairs(tabs) do b.Size = UDim2.new(0.5, -3, 1, -6) end
		itemsView.Position, itemsView.Size = UDim2.fromOffset(0, 4), UDim2.new(1, 0, 1, -4)
		search.Position, search.Size = UDim2.fromOffset(164, 0), UDim2.new(1, -164 - 96, 0, tall)
		gearView.Position, gearView.Size = UDim2.fromOffset(0, tall + 10), UDim2.new(1, 0, 1, -tall - 10)
	else
		tabRow.Position, tabRow.Size = UDim2.fromOffset(8, 6), UDim2.new(1, -16, 0, 30)
		for _, b in pairs(tabs) do b.Size = UDim2.new(0.5, -3, 0, 24) end
		itemsView.Position, itemsView.Size = UDim2.fromOffset(0, 40), UDim2.new(1, 0, 1, -40)
		search.Position, search.Size = UDim2.fromOffset(8, 0), UDim2.new(1, -96, 0, tall)
		gearView.Position, gearView.Size = itemsView.Position, itemsView.Size
	end
	sortButton.Size = UDim2.fromOffset(80, tall)
	grid.Position = UDim2.fromOffset(8, tall + 6)
	for _, b in ipairs({prevPage, nextPage}) do b.Size = UDim2.fromOffset(tall, tall) end
	footer.Size = UDim2.new(1, -16, 0, tall)
	pageLabel.Position = UDim2.fromOffset(tall + 4, 0)
	pageLabel.Size = UDim2.new(1, -2 * tall - 8, 1, 0)
	-- Paperdoll: 40 px slots (44 on touch) on the 3 × 4 grid, or one row on 303 px screens.
	local dollSize = if touch then 44 else 40
	local gap = dollSize + 6
	for i, d in ipairs(DOLL) do
		local b = S.doll[d.slot]
		b.Size = UDim2.fromOffset(dollSize, dollSize)
		if L.tiny then
			b.Position = UDim2.new(0, 8 + dollSize / 2 + (i - 1) * gap, 0, 6)
		else
			b.Position = UDim2.new(0.5, (d.col - 2) * (gap + 14), 0, 6 + (d.row - 1) * gap)
		end
	end
	figure.Visible = not L.tiny
	figure.Position, figure.Size = UDim2.new(0.5, 0, 0, 2), UDim2.fromOffset(dollSize + 14, 4 * gap + 2)
	if L.tiny then
		doll.Size = UDim2.new(0, 8 * gap + 10, 0, dollSize + 12)
		statsList.Position, statsList.Size = UDim2.new(0, 8 * gap + 26, 0, 0), UDim2.new(1, -8 * gap - 34, 1, -4)
	-- Wide panels: paperdoll left, stat sheet right; narrow: stacked.
	elseif width >= 300 then
		doll.Size = UDim2.new(0.5, -10, 0, 4 * gap + 8)
		statsList.Position, statsList.Size = UDim2.new(0.5, 2, 0, 0), UDim2.new(0.5, -10, 1, -4)
	else
		doll.Size = UDim2.new(1, -16, 0, 204)
		statsList.Position, statsList.Size = UDim2.fromOffset(8, 210), UDim2.new(1, -16, 1, -214)
	end
end
function S.refresh()
	if not panel.Visible then return end
	placePanel()
	itemsView.Visible = S.view == "Items"
	gearView.Visible = S.view == "Gear"
	T.selectTab(tabs, S.view)
	-- The last applied mode (snapshot satchelSort), not a click still in flight.
	sortButton.Text = "⇅ " .. string.upper(S.sort:sub(1, 1)) .. S.sort:sub(2)
	local items = tbl(S.snap and S.snap.items)
	if S.view == "Items" then
		local ids = visibleIds()
		local per = S.perPage
		local pages = math.max(1, math.ceil(#ids / per))
		S.page = math.clamp(S.page, 1, pages)
		S.pageIds = ids
		for i, b in ipairs(S.slots) do
			local id = if i <= per then ids[(S.page - 1) * per + i] else nil
			local def = id and Data.Items[id]
			b:SetAttribute("Index", (S.page - 1) * per + i)
			T.setSlot(b, {id = id, def = def, count = id and tonumber(items[id]) or 0, equipped = id ~= nil and (equippedSlot(id) ~= nil or bagged(id)),
				selected = id ~= nil and id == S.selected})
		end
		local coins = T.commas(tonumber(S.snap and S.snap.coins) or 0)
		pageLabel.Text = "Bag " .. S.page .. "/" .. pages .. "  ·  " .. #(S.all or ids) .. " items  ·  <font color=\"#F7C548\">◆ " .. coins .. "</font>"
		prevPage.Visible, nextPage.Visible = pages > 1, pages > 1
	else
		local eq = tbl(depth().equipment)
		for _, d in ipairs(DOLL) do
			local b = S.doll[d.slot]
			local id
			if d.slot == "accessory" then id = tbl(depth().accessoryBag)[1]
			elseif d.slot == "pet" then
				local pets = tbl(depth().pets)
				for _, pet in ipairs(pets) do if type(pet) == "table" and pet.active then id = Data.PetById and Data.PetById[pet.id] and (pet.id .. "Pet") end end
				if id and not Data.Items[id] then id = nil end
			else id = eq[d.slot] end
			T.setSlot(b, {id = id, def = id and Data.Items[id], count = if d.slot == "ammo" and id then tonumber(items[id]) or 0 else 0})
			b:FindFirstChild("SlotName").Visible = id == nil
		end
		local stats = tbl(depth().stats)
		for key, label in pairs(statRows) do
			local v = tonumber(stats[key])
			label.Text = if v then T.commas(v) .. (if Data.Stats[key].percent then "%" else "") else "—"
		end
	end
end
local function setOpen(open)
	S.open = open
	panel.Visible = open
	satchelShade.Visible = open and layout().short
	if not open then hideMenu(); tooltip.Visible = false; ghost.Visible = false; S.drag = nil; S.press = nil end
	S.refresh()
	local docked = open and S.docked == true
	if player:GetAttribute("IsleSatchelOpen") ~= docked then player:SetAttribute("IsleSatchelOpen", docked) end
end
S.setOpen = setOpen
-- Pin: the button tone, S.pinned and Settings › Pin the satchel
-- (IsleSettingPinSatchel) always agree, whichever side changes.
function S.setPinned(pinned)
	S.pinned = pinned == true
	T.tone(pin, if S.pinned then "selected" else "ghost")
	if (player:GetAttribute("IsleSettingPinSatchel") == true) ~= S.pinned then player:SetAttribute("IsleSettingPinSatchel", S.pinned) end
end
close.Activated:Connect(function() S.setPinned(false); setOpen(false) end)
satchelShade.Activated:Connect(function() setOpen(false) end)
pin.Activated:Connect(function()
	S.setPinned(not S.pinned)
	toast(if S.pinned then "Satchel pinned: it stays open while you play." else "Satchel unpinned.")
end)
sortButton.Activated:Connect(function()
	local i = table.find(T.SORTS, S.sort) or 1
	send("satchelSort", T.SORTS[i % #T.SORTS + 1])
	S.refresh()
end)
prevPage.Activated:Connect(function() S.page -= 1; S.refresh() end)
nextPage.Activated:Connect(function() S.page += 1; S.refresh() end)
search:GetPropertyChangedSignal("Text"):Connect(function() S.search = search.Text; S.page = 1; S.refresh() end)

-- Slot input: left click = primary option (OSRS), right click / long press =
-- context menu, hover = tooltip, drag a slot onto another slot = reorder.
-- A press tracks the InputObject that started it (one finger on touch), and
-- becomes a drag only after DRAG_START px of travel, so a long-press survives
-- small jitter.
local DRAG_START = 7
local function slotAt(pos)
	local origin, cell = grid.AbsolutePosition, (S.cell or 44) + 4
	local c, r = math.floor((pos.X - origin.X) / cell), math.floor((pos.Y - origin.Y) / cell)
	if c < 0 or r < 0 or c >= (S.cols or 4) or r >= S.perPage // (S.cols or 4) then return nil end
	return r * (S.cols or 4) + c + 1
end
-- The full-satchel position (what satchelMove expects) of a grid index; while
-- searching the grid is filtered, so the drop lands before the item shown there
-- (or after the last match when dropped past the end).
function S.fullIndex(index)
	local ids, all = S.pageIds or {}, S.all or {}
	local id = ids[index]
	if id then return table.find(all, id) or index end
	if S.search ~= "" and #ids > 0 then return table.find(all, ids[#ids]) or #all end
	return index
end
local function isPress(input) return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch end
-- True when this release / tap of slot i ended a drag or a long-press menu (the
-- Activated that follows in the same frame is swallowed; anything later is not).
local function consumed(key, i)
	local mark = S[key]
	S[key] = nil
	return mark ~= nil and mark.slots[i] == true and os.clock() - mark.at < 0.3
end
for i, b in ipairs(S.slots) do
	local function item() local ids = S.pageIds or {} return ids[(S.page - 1) * S.perPage + i] end
	b.MouseEnter:Connect(function() local id = item() if id and not S.drag and not menu.Visible then showTip(id, b.AbsolutePosition + Vector2.new(b.AbsoluteSize.X, 0)) end end)
	b.MouseLeave:Connect(function() tooltip.Visible = false end)
	b.MouseButton2Click:Connect(function() local id = item() if id then openMenu(id, b.AbsolutePosition + Vector2.new(b.AbsoluteSize.X, 0)) end end)
	b.InputBegan:Connect(function(input)
		if not isPress(input) or S.press then return end
		local id = item()
		if not id then return end
		local touchPress = input.UserInputType == Enum.UserInputType.Touch
		S.press = {id = id, from = i, at = os.clock(), moved = false, input = input, touch = touchPress, start = Vector2.new(input.Position.X, input.Position.Y)}
		if touchPress then
			local token = S.press
			task.delay(0.45, function()
				if S.press == token and not token.moved then
					S.press = nil
					S.longPressed = {at = os.clock(), slots = {[i] = true}}
					openMenu(id, b.AbsolutePosition + Vector2.new(b.AbsoluteSize.X * 0.5, 0))
				end
			end)
		end
	end)
	b.Activated:Connect(function()
		local id = item()
		if consumed("dragged", i) or consumed("longPressed", i) then return end
		if not id then hideMenu() return end
		if Input.TouchEnabled then
			-- Tap: select and show the lore; a second tap opens the menu.
			if S.selected == id then openMenu(id, b.AbsolutePosition + Vector2.new(b.AbsoluteSize.X * 0.5, 0))
			else S.selected = id; showTip(id, b.AbsolutePosition + Vector2.new(b.AbsoluteSize.X, 0)); S.refresh() end
			return
		end
		local ctx, def = S.ctx(id)
		local first = T.itemActions(def, ctx)[1]
		if first and first.verb then S.run(first, id) else openMenu(id, b.AbsolutePosition + Vector2.new(b.AbsoluteSize.X, 0)) end
	end)
end
Input.InputChanged:Connect(function(input)
	local press = S.press
	if not press then return end
	-- Touch: only the finger that started the press; mouse: mouse movement.
	if press.touch then
		if input ~= press.input then return end
	elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
	local pos = Vector2.new(input.Position.X, input.Position.Y)
	if not press.moved then
		if (pos - press.start).Magnitude < DRAG_START then return end
		press.moved = true
		S.drag = press
		T.setSlot(ghost, {id = press.id, def = Data.Items[press.id], count = tonumber(tbl(S.snap and S.snap.items)[press.id]) or 0})
		ghost.Visible = true
		tooltip.Visible = false
	end
	ghost.Position = UDim2.fromOffset(pos.X - 22, pos.Y - 22)
end)
Input.InputEnded:Connect(function(input)
	local press = S.press
	if not press or not isPress(input) then return end
	if press.touch and input ~= press.input then return end
	if not press.touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	local drag = S.drag
	S.press, S.drag = nil, nil
	ghost.Visible = false
	if not drag then return end
	local target = slotAt(Vector2.new(input.Position.X, input.Position.Y))
	-- Swallow only the click this release produces (on the origin or drop slot).
	S.dragged = {at = os.clock(), slots = {[drag.from] = true, [target or 0] = true}}
	if target and target ~= drag.from then
		send("satchelMove", drag.id .. ":" .. S.fullIndex((S.page - 1) * S.perPage + target))
	end
end)
for slot, b in pairs(S.doll) do
	b.Activated:Connect(function()
		-- The pet slot is the Pets page (its roster, levels and summons), not an item.
		if slot == "pet" then hudEvents:Fire("open", "Hero", "Pets") return end
		local id = b:GetAttribute("ItemId")
		if id == nil or id == "" then
			if slot == "accessory" then hudEvents:Fire("open", "Hero", "Accessories") end
			return
		end
		openMenu(id, b.AbsolutePosition + Vector2.new(b.AbsoluteSize.X, 0))
	end)
	b.MouseEnter:Connect(function() local id = b:GetAttribute("ItemId") if id and id ~= "" then showTip(id, b.AbsolutePosition + Vector2.new(b.AbsoluteSize.X, 0)) end end)
	b.MouseLeave:Connect(function() tooltip.Visible = false end)
end

------------------------------------------------------------------------------
-- XP drops (OSRS) and the skill progress toast
------------------------------------------------------------------------------
local drops = make("Frame", gui, {Name = "XpDrops", BackgroundTransparency = 1, Size = UDim2.fromOffset(170, 120), AnchorPoint = Vector2.new(1, 0)})
local dropPool, dropNext = {}, 1
for i = 1, 5 do
	local l = T.label(drops, {Name = "Drop" .. i, Text = "", Size = UDim2.fromOffset(170, 20), AnchorPoint = Vector2.new(1, 0), TextXAlignment = Enum.TextXAlignment.Right,
		Font = T.font.number, TextSize = 11, TextStrokeTransparency = 0.2, TextStrokeColor3 = C.void, RichText = true, Visible = false, TextTruncate = Enum.TextTruncate.None})
	dropPool[i] = l
end
local skillToast = T.frame(gui, {name = "SkillToast", size = UDim2.fromOffset(230, 46), ornate = false, rimThickness = 1.5, visible = false, transparency = 0.1})
local toastSkill = T.label(skillToast, {Name = "Skill", Position = UDim2.fromOffset(10, 5), Size = UDim2.new(1, -20, 0, 16), Font = T.font.label, TextSize = 12, RichText = true})
local toastBar = T.bar(skillToast, {name = "Progress", position = UDim2.fromOffset(10, 25), size = UDim2.new(1, -20, 0, 13), height = 13, textSize = 10})
S.toastToken = 0
-- The XP lane (Theme.hudLayout xpDrops / xpToast): its own column left of the
-- right-column HUDs (party, minigame, lair, world boss board), so drops never
-- sit on them; it steps left with them when the satchel docks.
local function placeDrops()
	local L = layout()
	local d, t = L.xpDrops, L.xpToast
	drops.Position, drops.Size = UDim2.fromOffset(d.x + d.w, d.y), UDim2.fromOffset(d.w, d.h)
	S.dropLines = d.lines or 5
	for _, l in ipairs(dropPool) do l.Size = UDim2.fromOffset(d.w, 20) end
	skillToast.Position, skillToast.Size = UDim2.fromOffset(t.x, t.y), UDim2.fromOffset(t.w, t.h)
	local slim = t.h < 46
	toastSkill.Position = UDim2.fromOffset(10, if slim then 2 else 5)
	toastBar.Position = UDim2.fromOffset(10, t.h - (if slim then 16 else 21))
	S.toastCompact = t.compact == true
end
S.placeDrops = placeDrops
-- gains: {{skill, amount, level, fraction, maxed, color}, ...}
local function showGains(gains)
	if type(gains) ~= "table" or player:GetAttribute("IsleSettingXpDrops") == false then return end
	placeDrops()
	-- Reduced motion (Settings or the device): drops appear in place and clear
	-- after a moment instead of drifting and fading.
	local still = T.reducedMotion(player)
	local width = drops.Size.X.Offset
	for k, g in ipairs(gains) do
		if k > math.min(3, S.dropLines or 5) then break end
		local l = dropPool[dropNext]
		dropNext = dropNext % #dropPool + 1
		l.Text = "<font color=\"#" .. (g.color or "F7C548") .. "\">+" .. T.commas(g.amount) .. "</font> " .. T.escape(g.skill) .. " XP"
		l.TextTransparency = 0
		l.TextStrokeTransparency = 0.2
		-- Newest at the foot of the column, drifting up and fading (OSRS drops).
		local foot = drops.Size.Y.Offset - 20
		l.Position = UDim2.fromOffset(width, foot - (k - 1) * 20)
		l.Visible = true
		local text = l.Text
		if still then
			task.delay(1.7, function() if l.Text == text then l.Visible = false end end)
		else
			TweenService:Create(l, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = UDim2.fromOffset(width, math.max(0, foot - 40) - (k - 1) * 20), TextTransparency = 1, TextStrokeTransparency = 1}):Play()
			task.delay(1.7, function() if l.TextTransparency >= 1 then l.Visible = false end end)
		end
	end
	local g = gains[1]
	if g then
		S.toastToken += 1
		local token = S.toastToken
		toastSkill.Text = if S.toastCompact then "<font color=\"#" .. (g.color or "F7C548") .. "\">+" .. T.commas(g.amount) .. "</font> " .. T.escape(g.skill)
			else "<font color=\"#" .. (g.color or "F7C548") .. "\">" .. T.escape(g.skill) .. " " .. tostring(g.level or "") .. "</font>  <font color=\"#A9B4C0\">+" .. T.commas(g.amount) .. " XP</font>"
		toastBar:FindFirstChild("Fill").BackgroundColor3 = T.rgb(g.color or "8EE05A")
		T.setBar(toastBar, g.fraction or 0, if g.maxed then "MAX" else (math.floor((g.fraction or 0) * 1000 + 0.5) / 10 .. "%"))
		skillToast.Visible = true
		task.delay(3, function() if token == S.toastToken then skillToast.Visible = false end end)
	end
end
xpEvents.Event:Connect(showGains)

-- (Region entry title cards are the World Art & Regions team's regions.client.lua, §30.)

------------------------------------------------------------------------------
-- Sky Chart: the floating islands as illustrated tiles with warp points.
------------------------------------------------------------------------------
local chartShade = make("TextButton", gui, {Name = "ChartShade", Text = "", AutoButtonColor = false, BackgroundColor3 = C.void, BackgroundTransparency = 0.35,
	BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 19, Selectable = false})
local chart = T.frame(gui, {name = "WarpMap", title = "SKY CHART", size = UDim2.fromScale(1, 1), visible = false, zIndex = 20, transparency = 0.04})
make("UISizeConstraint", chart, {MaxSize = Vector2.new(980, 640)})
chart.AnchorPoint, chart.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
local chartBody = chart:FindFirstChild("Body")
local chartHint = T.label(chartBody, {Name = "Hint", Text = "Choose a warp point to travel there. Locked isles show what opens them.", Position = UDim2.fromOffset(14, 4),
	Size = UDim2.new(1, -28, 0, 18), TextColor3 = C.dim, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center})
local sky = make("Frame", chartBody, {Name = "Sky", BackgroundColor3 = T.rgb("2B4A6F"), BorderSizePixel = 0, Position = UDim2.fromOffset(10, 26), Size = UDim2.new(1, -20, 1, -36), ClipsDescendants = true})
T.corner(sky, 6)
make("UIGradient", sky, {Rotation = 90, Color = ColorSequence.new(T.rgb("5C86B8"), T.rgb("1A2C44"))})
for i, cloud in ipairs({{0.1, 0.15, 0.22}, {0.72, 0.1, 0.18}, {0.45, 0.82, 0.26}, {0.86, 0.66, 0.16}, {0.2, 0.7, 0.14}}) do
	local f = make("Frame", sky, {Name = "Cloud" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(cloud[1], cloud[2]), Size = UDim2.fromScale(cloud[3], cloud[3] * 0.35),
		BackgroundColor3 = C.white, BackgroundTransparency = 0.9, BorderSizePixel = 0, ZIndex = 1})
	T.corner(f, 40)
end
local chartClose = T.button(chart, "✕", {name = "CloseChart", size = UDim2.fromOffset(44, 26), anchor = Vector2.new(1, 0), position = UDim2.new(1, -6, 0, 2), tone = "ghost", textSize = 14})
local chartInfo = T.frame(chartBody, {name = "WarpInfo", size = UDim2.fromOffset(260, 74), ornate = false, rimThickness = 1, visible = false, zIndex = 30})
local infoTitle = T.label(chartInfo, {Name = "Title", Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 18), Font = T.font.label, TextSize = 14, ZIndex = 31, RichText = true})
local infoText = T.label(chartInfo, {Name = "Detail", Position = UDim2.fromOffset(10, 24), Size = UDim2.new(1, -20, 0, 16), TextSize = 12, TextColor3 = C.dim, ZIndex = 31, RichText = true})
local infoGo = T.button(chartInfo, "Travel", {name = "TravelButton", position = UDim2.new(0, 10, 1, -30), size = UDim2.new(1, -20, 0, 24), tone = "primary", textSize = 12})
infoGo.ZIndex = 32
S.tiles = {}
local function regionState(region)
	if region == "Home" then return true, "" end
	for _, r in ipairs(tbl(depth().regions)) do
		if type(r) == "table" and r.id == region then return r.unlocked ~= false, r.requirement or "" end
	end
	local attr = player:GetAttribute(region .. "Unlocked")
	if attr == false then
		local def = Data.RegionById and Data.RegionById[region]
		local need = {}
		for skill, lvl in pairs(tbl(def and def.requires and def.requires.skills)) do table.insert(need, skill .. " " .. lvl) end
		table.sort(need)
		return false, table.concat(need, ", ")
	end
	return true, ""
end
-- Floating-island tile: a grassy crown (ellipse) with tree tufts, a layered
-- rock underside with stalactites, the name plate below and a violet warp
-- point (or a drawn padlock when the isle is still locked).
local function tile(island)
	local t = make("Frame", sky, {Name = "Isle_" .. island.id, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(island.u, island.v),
		Size = UDim2.fromOffset(island.size, island.size * 0.78), BackgroundTransparency = 1, ZIndex = 2})
	local top = T.rgb(island.top or "8DB86E")
	local rockTop, rockFoot = T.rgb("7A6650"), T.rgb("2A211A")
	local function plate(name, x, y, w, h, color, radius, rot)
		local f = make("Frame", t, {Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h),
			BackgroundColor3 = color, BorderSizePixel = 0, Rotation = rot or 0})
		if radius then T.corner(f, radius) end
		return f
	end
	-- Underside: a broad slab, two stalactites and a long central spire.
	local slab = plate("Rock", 0.5, 0.52, 0.9, 0.44, rockTop, 18)
	make("UIGradient", slab, {Rotation = 90, Color = ColorSequence.new(rockTop, rockFoot)})
	for i, s in ipairs({{0.28, 0.68, 0.2}, {0.72, 0.66, 0.18}, {0.5, 0.76, 0.3}}) do
		local spike = plate("Spike" .. i, s[1], s[2], s[3], s[3], T.darken(rockTop, 0.35 + i * 0.05), nil, 45)
		make("UIGradient", spike, {Rotation = 45, Color = ColorSequence.new(T.darken(rockTop, 0.2), rockFoot)})
	end
	-- Crown: grass ellipse with a lit rim and tufts.
	local grass = plate("Top", 0.5, 0.34, 1, 0.44, top, 80)
	make("UIGradient", grass, {Rotation = 90, Color = ColorSequence.new(T.lighten(top, 0.3), T.darken(top, 0.15))})
	make("UIStroke", grass, {Color = T.darken(top, 0.6), Thickness = 1.5})
	for i, tuft in ipairs({{0.22, 0.3, 0.12}, {0.34, 0.24, 0.1}, {0.72, 0.28, 0.13}, {0.62, 0.42, 0.09}, {0.28, 0.44, 0.08}}) do
		local f = plate("Tuft" .. i, tuft[1], tuft[2], tuft[3], tuft[3] * 1.25, T.darken(top, 0.35), 40)
		make("UIStroke", f, {Color = T.darken(top, 0.6), Thickness = 1})
	end
	local name = T.label(t, {Name = "Name", Text = island.name, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.84), Size = UDim2.fromOffset(170, 16),
		TextXAlignment = Enum.TextXAlignment.Center, Font = T.font.label, TextSize = 12, TextStrokeTransparency = 0.15, TextStrokeColor3 = C.void, ZIndex = 4})
	local warp = make("TextButton", t, {Name = "Warp", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.26), Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = T.rgb("6A3FC8"), Text = "✦", Font = T.font.heading, TextSize = 16, TextColor3 = C.white, AutoButtonColor = true, ZIndex = 5})
	T.corner(warp, 16)
	make("UIGradient", warp, {Rotation = 90, Color = ColorSequence.new(T.rgb("E8DAFF"), T.rgb("8C6AD8"))})
	make("UIStroke", warp, {Color = T.rgb("F2E9FF"), Thickness = 2})
	-- Padlock drawn from frames: shackle ring over a gold body.
	local lock = make("Frame", t, {Name = "Lock", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.26), Size = UDim2.fromOffset(22, 24),
		BackgroundTransparency = 1, Visible = false, ZIndex = 6})
	local shackle = make("Frame", lock, {Name = "Shackle", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 1, ZIndex = 6})
	T.corner(shackle, 7)
	make("UIStroke", shackle, {Color = T.rgb("C9D2DC"), Thickness = 3})
	local body = make("Frame", lock, {Name = "Body", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(22, 14),
		BackgroundColor3 = C.gold, BorderSizePixel = 0, ZIndex = 7})
	T.corner(body, 3)
	make("UIStroke", body, {Color = C.frameLo, Thickness = 1})
	local here = T.label(t, {Name = "Here", Text = "YOU ARE HERE", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.02), Size = UDim2.fromOffset(110, 12),
		TextXAlignment = Enum.TextXAlignment.Center, Font = T.font.number, TextSize = 8, TextColor3 = C.gold, Visible = false, ZIndex = 6, TextStrokeTransparency = 0.1, TextStrokeColor3 = C.void})
	-- The whole isle is a button (under the warp point), so a locked isle with
	-- no warp point still opens its card with the requirement.
	local pickButton = make("TextButton", t, {Name = "TileButton", Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3,
		AutoButtonColor = false, Selectable = true})
	local pick = function() S.pickWarp(island, t) end
	warp.Activated:Connect(pick)
	pickButton.Activated:Connect(pick)
	S.tiles[island.id] = {frame = t, warp = warp, lock = lock, here = here, name = name, island = island, grass = grass, button = pickButton}
	return t
end
for _, island in ipairs(T.WorldMap.islands) do tile(island) end
tile(T.WorldMap.home)
function S.pickWarp(island, frame)
	local unlocked, requirement = regionState(island.region)
	S.warpPick = island
	chartInfo.Visible = true
	-- Beside the tile, on the side with more room.
	local right = island.u > 0.6
	chartInfo.AnchorPoint = Vector2.new(if right then 1 else 0, 0.5)
	chartInfo.Position = UDim2.new(island.u, if right then -island.size / 2 - 8 else island.size / 2 + 8, island.v, 0)
	infoTitle.Text = T.escape(island.name)
	if not unlocked then
		infoText.Text = "<font color=\"#FF6B5A\">Locked</font> · " .. T.escape(if requirement ~= "" then requirement else "Not charted yet")
		infoGo.Text = "Locked"
		T.tone(infoGo, "ghost")
	else
		infoText.Text = if island.travel == "recall" then "Recall charm · instant travel" else "Guided route to its skyway beacon"
		infoGo.Text = if island.travel == "recall" then "Travel" else "Guide me"
		T.tone(infoGo, "primary")
	end
	infoGo:SetAttribute("Locked", not unlocked)
end
-- Map Art (§32, shared/MapArt.lua): the 3D miniature archipelago, clouds,
-- glowing warp points, pan / zoom and insets; the tiles above stay the warp
-- buttons (and the whole chart when the islands are not in the world yet).
do
	local module = ReplicatedStorage:FindFirstChild("AetherMapArt")
	local ok, MapArt = pcall(function() return module and require(module) end)
	if ok and type(MapArt) == "table" and MapArt.mountChart then
		S.art = MapArt.mountChart({sky = sky, chart = chart, info = chartInfo, hint = chartHint, state = S, regionState = regionState, Theme = T, Data = Data,
			touch = Input.TouchEnabled, Input = Input, TweenService = TweenService, workspace = workspace, player = player,
			forge = function(host) local api = ReplicatedStorage:FindFirstChild("MeshForgeLocal") if api then return api:Invoke("visual", host) end return nil end})
	end
end
infoGo.Activated:Connect(function()
	local island = S.warpPick
	if not island or infoGo:GetAttribute("Locked") then return end
	if island.travel == "recall" then
		send("recall", island.target)
	else
		local request = player:FindFirstChild("WayfinderRequest")
		if request then request:Fire(island.specs, island.name) else toast("The Wayfinder is still charting. Try again in a moment.") end
	end
	S.setChart(false)
end)
local function refreshChart()
	local here = player:GetAttribute("IsleRegionHere")
	local L = layout()
	chart.Size = UDim2.new(1, -16, 1, -16)
	chartHint.Visible = not L.tiny
	-- Touch: 44 px close and travel buttons (a taller header and info card).
	local touch = Input.TouchEnabled or L.short
	local headerH = if touch then 46 else 28
	chart:FindFirstChild("Header").Size = UDim2.new(1, -6, 0, headerH - 3)
	chart:FindFirstChild("HeaderRule").Position = UDim2.new(0, 10, 0, headerH)
	chartBody.Position, chartBody.Size = UDim2.fromOffset(0, headerH), UDim2.new(1, 0, 1, -headerH)
	chartClose.Size, chartClose.Position = UDim2.fromOffset(44, if touch then 44 else 26), UDim2.new(1, -6, 0, if touch then 1 else 2)
	chartInfo.Size = UDim2.fromOffset(260, if touch then 96 else 74)
	infoGo.Position, infoGo.Size = UDim2.new(0, 10, 1, if touch then -50 else -30), UDim2.new(1, -20, 0, if touch then 44 else 24)
	sky.Position, sky.Size = UDim2.fromOffset(10, if L.tiny then 4 else 26), UDim2.new(1, -20, 1, if L.tiny then -12 else -36)
	local area = sky.AbsoluteSize
	S.chartScale = math.clamp(math.min(area.X / 940, area.Y / 520), 0.55, 1)
	for id, t in pairs(S.tiles) do
		local unlocked = regionState(t.island.region)
		t.lock.Visible = not unlocked
		t.warp.Visible = unlocked
		local size = math.floor(t.island.size * S.chartScale)
		t.frame.Size = UDim2.fromOffset(size, math.floor(size * 0.78))
		local warpSize = if Input.TouchEnabled then 44 else 32
		t.warp.Size = UDim2.fromOffset(warpSize, warpSize)
		t.warp:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, warpSize // 2)
		t.grass.BackgroundTransparency = if unlocked then 0 else 0.45
		t.name.TextColor3 = if unlocked then C.text else C.dim
		t.here.Visible = here ~= nil and (here == t.island.region and (id == t.island.region or (id == "Hub" and here == "Hub")))
		t.name.TextSize = if L.short then 10 else 12
		t.name.Visible = not L.tiny or unlocked
	end
	if S.art then S.art.refresh() end -- Map Art (§32): miniature, overlay and locks
end
local function setChart(open)
	chart.Visible = open
	chartShade.Visible = open
	chartInfo.Visible = false
	if open then refreshChart(); setOpen(S.pinned and S.open) end
end
S.setChart = setChart
chartClose.Activated:Connect(function() setChart(false) end)
chartShade.Activated:Connect(function() setChart(false) end)

------------------------------------------------------------------------------
-- Wiring
------------------------------------------------------------------------------
local function accept(snap)
	if type(snap) ~= "table" or type(snap.items) ~= "table" then return end
	S.snap = snap
	-- The sort label shows the last mode the server applied (saved with p.satchel).
	if type(snap.satchelSort) == "string" and table.find(T.SORTS, snap.satchelSort) then S.sort = snap.satchelSort end
	if S.open then S.refresh() end
	if chart.Visible then refreshChart() end
end
channel("IsleSnapshotLocal").Event:Connect(accept)
task.spawn(function()
	local updates = ReplicatedStorage:WaitForChild("IsleUpdate", 30)
	if updates then updates.OnClientEvent:Connect(accept) end
end)
hudEvents.Event:Connect(function(kind)
	if kind == "satchel" then setOpen(not S.open)
	elseif kind == "gear" then S.view = "Gear"; setOpen(true)
	elseif kind == "warpmap" then setChart(not chart.Visible)
	end
end)
Input.InputBegan:Connect(function(input, used)
	if used then return end
	local key = input.KeyCode
	-- E is also the default ProximityPrompt key: while a prompt is on screen it
	-- belongs to the prompt (Tab always works).
	if (key == Enum.KeyCode.E and not S.promptShowing()) or key == Enum.KeyCode.Tab then setOpen(not S.open)
	elseif key == Enum.KeyCode.M then setChart(not chart.Visible)
	elseif key == Enum.KeyCode.Escape then hideMenu(); setChart(false)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 and menu.Visible then
		task.defer(function() if menu.Visible and S.menuFor and not S.confirm then hideMenu() end end)
	end
end)
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if S.open then S.refresh() end end)
player:GetAttributeChangedSignal("IsleSettingPinSatchel"):Connect(function()
	S.setPinned(player:GetAttribute("IsleSettingPinSatchel") == true)
	if S.pinned and dockable() then setOpen(true) end
end)
actions:Fire("snapshot")
-- Chat-safe layout: the minimap owns the top-left, so on desktop the chat
-- window docks bottom-left (the lane Theme.hudLayout keeps clear, under the
-- left column). Touch devices keep Roblox's default chat position.
S.chatDocked = not Input.TouchEnabled
pcall(function()
	local config = game:GetService("TextChatService"):FindFirstChildOfClass("ChatWindowConfiguration")
	if config and S.chatDocked then
		config.VerticalAlignment = Enum.VerticalAlignment.Bottom
		config.HorizontalAlignment = Enum.HorizontalAlignment.Left
	end
end)
-- Test / tooling handle (no gameplay effect).
S.panel, S.menu, S.tooltip, S.chart, S.drops, S.skillToast, S.gui = panel, menu, tooltip, chart, drops, skillToast, gui
local api = Instance.new("BindableFunction")
api.Name = "IsleHudApi"
api.OnInvoke = function(method, ...)
	if method == "state" then return S end
	if method == "open" then setOpen(true) return true end
	if method == "menu" then openMenu(..., Vector2.new(200, 200)) return true end
	if method == "chart" then setChart(true) return true end
	return nil
end
api.Parent = player
