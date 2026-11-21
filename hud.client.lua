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
-- Opened by: E / Tab, the sidebar's Satchel button and IsleHudLocal:Fire("satchel").
-- Local attributes published: IsleSatchelOpen (docked on desktop; the right
-- column HUDs step left of it).
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
local PER_PAGE = 28
local function tbl(v) return if type(v) == "table" then v else {} end
local function screen()
	local size = gui.AbsoluteSize
	if size and size.X > 0 and size.Y > 0 then return size end
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1366, 768)
end
local function layout() return T.hudLayout(screen().X, screen().Y, {touch = Input.TouchEnabled, satchelOpen = S.open and S.docked}) end
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
do -- silhouette behind the slots
	local function part(x, y, w, h, r)
		local f = make("Frame", doll, {Name = "Figure", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, x, 0, y), Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = C.raised, BackgroundTransparency = 0.55, BorderSizePixel = 0})
		T.corner(f, r or 6)
	end
	part(0, 34, 34, 34, 17); part(0, 86, 46, 60, 8); part(0, 144, 40, 50, 6); part(0, 186, 46, 14, 4)
end
-- OSRS equipment layout: head top, cape/amulet row, weapon-body-shield row, legs, feet.
local DOLL = {
	{slot = "helmet", label = "Head", x = 0, y = 12}, {slot = "accessory", label = "Bag", x = -62, y = 44}, {slot = "pet", label = "Pet", x = 62, y = 44},
	{slot = "weapon", label = "Weapon", x = -62, y = 96}, {slot = "chest", label = "Body", x = 0, y = 76}, {slot = "ammo", label = "Quiver", x = 62, y = 96},
	{slot = "legs", label = "Legs", x = 0, y = 124}, {slot = "boots", label = "Feet", x = 0, y = 166},
}
for _, d in ipairs(DOLL) do
	local b = T.slot(doll, {name = "Equip" .. d.slot, size = 38})
	b.AnchorPoint = Vector2.new(0.5, 0)
	b.Position = UDim2.new(0.5, d.x, 0, d.y)
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
	return {Data = Data, count = tonumber(tbl(S.snap and S.snap.items)[id]) or 0, equipped = equippedSlot(id) ~= nil, bagged = bagged(id),
		levels = levels(), enchants = tbl(depth().enchants)[id]}, def
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
		toast(option.label .. " " .. def.name .. "? Choose it again to confirm.")
		return false
	end
	S.confirm = nil
	if option.verb then
		send(option.verb, option.arg)
	elseif option["local"] == "examine" then
		toast(T.examine(def))
	elseif option["local"] == "hotbar" then
		local api = ReplicatedStorage:FindFirstChild("HotbarApi")
		local ok, done, message = false, false, nil
		if api then
			ok, done, message = pcall(function()
				local slots = api:Invoke("getSlots")
				local target = 3
				for i = 3, 9 do if type(slots) == "table" and type(slots.slots) == "table" and not slots.slots[i] then target = i; break end end
				return api:Invoke("assign", target, id)
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
	S.docked = not L.short and not Input.TouchEnabled
	local rect = L.satchel
	-- Grid shapes (always 28 slots): 7 × 4 on the docked panel and the phone
	-- modal, 14 × 2 on the shortest phones.
	local cols = if L.tiny then 14 elseif rect.w >= 300 then 7 else 4
	local rows = PER_PAGE // cols
	local tall = if touch then 44 else 28
	local toolbar = if touch then 4 + tall + 6 else 6 + 30 + 4 + tall + 6
	local pager = tall + 8
	local cellMin = if touch then 44 else 34
	local cell = math.floor(math.min((rect.w - 16 - (cols - 1) * 4) / cols, 52))
	cell = math.max(cell, cellMin)
	local width = math.max(rect.w, cols * (cell + 4) + 12)
	local height = math.min(rect.h, 28 + toolbar + rows * (cell + 4) + pager)
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
	end
	S.cell, S.cols = cell, cols
	grid.Size = UDim2.new(1, -16, 0, rows * (cell + 4))
	close.Size = UDim2.fromOffset(if touch then 44 else 26, if touch then 26 else 22)
	close.Position = UDim2.new(1, -4, 0, if touch then 1 else 3)
	pin.Visible = S.docked
	local tabRow = tabs.Items.Parent
	if touch then
		-- One toolbar row: [Items|Gear] [search…] [sort].
		tabRow.Position, tabRow.Size = UDim2.fromOffset(8, 4), UDim2.fromOffset(150, tall)
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
	-- Wide panels: paperdoll left, stat sheet right; narrow: stacked.
	if width >= 300 then
		doll.Size = UDim2.new(0.5, -10, 0, math.min(204, height - 28 - (if touch then tall + 10 else 40) - 6))
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
	sortButton.Text = "⇅ " .. string.upper(S.sort:sub(1, 1)) .. S.sort:sub(2)
	local items = tbl(S.snap and S.snap.items)
	if S.view == "Items" then
		local ids = visibleIds()
		local pages = math.max(1, math.ceil(#ids / PER_PAGE))
		S.page = math.clamp(S.page, 1, pages)
		S.pageIds = ids
		for i, b in ipairs(S.slots) do
			local id = ids[(S.page - 1) * PER_PAGE + i]
			local def = id and Data.Items[id]
			b:SetAttribute("Index", (S.page - 1) * PER_PAGE + i)
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
	if not open then hideMenu(); tooltip.Visible = false; ghost.Visible = false; S.drag = nil end
	S.refresh()
	local docked = open and S.docked == true
	if player:GetAttribute("IsleSatchelOpen") ~= docked then player:SetAttribute("IsleSatchelOpen", docked) end
end
S.setOpen = setOpen
close.Activated:Connect(function() S.pinned = false; setOpen(false) end)
pin.Activated:Connect(function()
	S.pinned = not S.pinned
	T.tone(pin, if S.pinned then "selected" else "ghost")
	toast(if S.pinned then "Satchel pinned: it stays open while you play." else "Satchel unpinned.")
end)
sortButton.Activated:Connect(function()
	local i = table.find(T.SORTS, S.sort) or 1
	S.sort = T.SORTS[i % #T.SORTS + 1]
	send("satchelSort", S.sort)
	S.refresh()
end)
prevPage.Activated:Connect(function() S.page -= 1; S.refresh() end)
nextPage.Activated:Connect(function() S.page += 1; S.refresh() end)
search:GetPropertyChangedSignal("Text"):Connect(function() S.search = search.Text; S.page = 1; S.refresh() end)

-- Slot input: left click = primary option (OSRS), right click / long press =
-- context menu, hover = tooltip, drag = reorder (or drop on the paperdoll).
local function slotAt(pos)
	local origin, cell = grid.AbsolutePosition, (S.cell or 44) + 4
	local c, r = math.floor((pos.X - origin.X) / cell), math.floor((pos.Y - origin.Y) / cell)
	if c < 0 or r < 0 or c >= (S.cols or 4) or r >= PER_PAGE // (S.cols or 4) then return nil end
	return r * (S.cols or 4) + c + 1
end
for i, b in ipairs(S.slots) do
	local function item() local ids = S.pageIds or {} return ids[(S.page - 1) * PER_PAGE + i] end
	b.MouseEnter:Connect(function() local id = item() if id and not S.drag and not menu.Visible then showTip(id, b.AbsolutePosition + Vector2.new(b.AbsoluteSize.X, 0)) end end)
	b.MouseLeave:Connect(function() tooltip.Visible = false end)
	b.MouseButton2Click:Connect(function() local id = item() if id then openMenu(id, b.AbsolutePosition + Vector2.new(b.AbsoluteSize.X, 0)) end end)
	b.MouseButton1Down:Connect(function()
		local id = item()
		if not id then return end
		S.press = {id = id, from = i, at = os.clock(), moved = false}
		if Input.TouchEnabled then
			local token = S.press
			task.delay(0.45, function()
				if S.press == token and not token.moved then
					S.press = nil
					openMenu(id, b.AbsolutePosition + Vector2.new(b.AbsoluteSize.X * 0.5, 0))
				end
			end)
		end
	end)
	b.Activated:Connect(function()
		local id = item()
		if not id then hideMenu() return end
		if S.dragged then S.dragged = false return end
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
	if not press or (input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch) then return end
	local pos = Vector2.new(input.Position.X, input.Position.Y)
	if not press.moved then
		press.moved = true
		S.drag = press
		T.setSlot(ghost, {id = press.id, def = Data.Items[press.id], count = tonumber(tbl(S.snap and S.snap.items)[press.id]) or 0})
		ghost.Visible = true
		tooltip.Visible = false
	end
	ghost.Position = UDim2.fromOffset(pos.X - 22, pos.Y - 22)
end)
Input.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
	local drag = S.drag
	S.press, S.drag = nil, nil
	ghost.Visible = false
	if not drag then return end
	S.dragged = true
	local pos = Vector2.new(input.Position.X, input.Position.Y)
	local target = slotAt(pos)
	if target and target ~= drag.from then
		local index = (S.page - 1) * PER_PAGE + target
		send("satchelMove", drag.id .. ":" .. index)
	end
end)
for slot, b in pairs(S.doll) do
	b.Activated:Connect(function()
		local id = b:GetAttribute("ItemId")
		if id == nil or id == "" then
			if slot == "accessory" then hudEvents:Fire("open", "Hero", "Accessories") elseif slot == "pet" then hudEvents:Fire("open", "Hero", "Pets") end
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
local function placeDrops()
	local L = layout()
	-- Tiny phones: the toast first, then two drop lines (clear of the Attack button).
	drops.Size = UDim2.fromOffset(170, if L.tiny then 42 elseif L.short then 62 else 120)
	drops.Position = UDim2.fromOffset(L.sidebar.x + L.sidebar.w, L.rightTop + (if L.tiny then 50 else 0))
	if S.open and S.docked then drops.Position = UDim2.fromOffset(L.satchel.x - 8, L.rightTop) end
	-- The progress toast sits under the drops column (right side, OSRS-style).
	local tw = if L.short then 190 else 230
	skillToast.Size = UDim2.fromOffset(tw, 46)
	local right = if S.open and S.docked then L.satchel.x - 8 else L.sidebar.x + L.sidebar.w
	skillToast.Position = UDim2.fromOffset(right - tw, L.rightTop + (if L.tiny then 0 elseif L.short then 66 else 124))
end
-- gains: {{skill, amount, level, fraction, maxed, color}, ...}
local function showGains(gains)
	if type(gains) ~= "table" or player:GetAttribute("IsleSettingXpDrops") == false then return end
	placeDrops()
	for k, g in ipairs(gains) do
		if k > 3 then break end
		local l = dropPool[dropNext]
		dropNext = dropNext % #dropPool + 1
		l.Text = "<font color=\"#" .. (g.color or "F7C548") .. "\">+" .. T.commas(g.amount) .. "</font> " .. T.escape(g.skill) .. " XP"
		l.TextTransparency = 0
		l.TextStrokeTransparency = 0.2
		-- Newest at the foot of the column, drifting up and fading (OSRS drops).
		local foot = drops.Size.Y.Offset - 20
		l.Position = UDim2.fromOffset(170, foot - (k - 1) * 20)
		l.Visible = true
		TweenService:Create(l, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = UDim2.fromOffset(170, math.max(0, foot - 40) - (k - 1) * 20), TextTransparency = 1, TextStrokeTransparency = 1}):Play()
		task.delay(1.7, function() if l.TextTransparency >= 1 then l.Visible = false end end)
	end
	local g = gains[1]
	if g then
		S.toastToken += 1
		local token = S.toastToken
		toastSkill.Text = "<font color=\"#" .. (g.color or "F7C548") .. "\">" .. T.escape(g.skill) .. " " .. tostring(g.level or "") .. "</font>  <font color=\"#A9B4C0\">+" .. T.commas(g.amount) .. " XP</font>"
		toastBar:FindFirstChild("Fill").BackgroundColor3 = T.rgb(g.color or "8EE05A")
		T.setBar(toastBar, g.fraction or 0, if g.maxed then "MAX" else (math.floor((g.fraction or 0) * 1000 + 0.5) / 10 .. "%"))
		skillToast.Visible = true
		task.delay(3, function() if token == S.toastToken then skillToast.Visible = false end end)
	end
end
xpEvents.Event:Connect(showGains)

------------------------------------------------------------------------------
-- Sky Chart: the floating islands as illustrated tiles with warp points.
------------------------------------------------------------------------------
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
		BackgroundColor3 = C.white, BackgroundTransparency = 0.86, BorderSizePixel = 0})
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
local function tile(island, x, y, size)
	local t = make("Frame", sky, {Name = "Isle_" .. island.id, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromOffset(size, size * 0.8),
		BackgroundTransparency = 1})
	local top = T.rgb(island.top or "8DB86E")
	-- Rock underside (two stacked plates narrowing down), grassy top, rim light.
	local rock = make("Frame", t, {Name = "Rock", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.34), Size = UDim2.fromScale(0.78, 0.42),
		BackgroundColor3 = T.rgb("5A4A3C"), BorderSizePixel = 0})
	T.corner(rock, 14)
	make("UIGradient", rock, {Rotation = 90, Color = ColorSequence.new(T.rgb("7A6450"), T.rgb("2E241C"))})
	local spike = make("Frame", t, {Name = "Spike", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.74), Size = UDim2.fromScale(0.3, 0.3),
		Rotation = 45, BackgroundColor3 = T.rgb("3A2E24"), BorderSizePixel = 0})
	local grass = make("Frame", t, {Name = "Top", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.34), Size = UDim2.fromScale(1, 0.46),
		BackgroundColor3 = top, BorderSizePixel = 0})
	T.corner(grass, 60)
	make("UIGradient", grass, {Rotation = 90, Color = ColorSequence.new(T.lighten(top, 0.25), T.darken(top, 0.2))})
	make("UIStroke", grass, {Color = T.darken(top, 0.55), Thickness = 1.5})
	local name = T.label(t, {Name = "Name", Text = island.name, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.9), Size = UDim2.fromOffset(160, 16),
		TextXAlignment = Enum.TextXAlignment.Center, Font = T.font.label, TextSize = 12, TextStrokeTransparency = 0.2, TextStrokeColor3 = C.void, ZIndex = 4})
	local warp = make("TextButton", t, {Name = "Warp", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = T.rgb("6A3FC8"), Text = "✦", Font = T.font.heading, TextSize = 15, TextColor3 = C.white, AutoButtonColor = true, ZIndex = 5})
	T.corner(warp, 15)
	make("UIStroke", warp, {Color = T.rgb("E2D0FF"), Thickness = 2})
	local lock = T.label(t, {Name = "Lock", Text = "🔒", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(30, 30),
		TextXAlignment = Enum.TextXAlignment.Center, TextSize = 16, Visible = false, ZIndex = 6})
	local here = T.label(t, {Name = "Here", Text = "▼ YOU", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.02), Size = UDim2.fromOffset(60, 12),
		TextXAlignment = Enum.TextXAlignment.Center, Font = T.font.number, TextSize = 8, TextColor3 = C.gold, Visible = false, ZIndex = 6, TextStrokeTransparency = 0.2})
	warp.Activated:Connect(function() S.pickWarp(island, t) end)
	S.tiles[island.id] = {frame = t, warp = warp, lock = lock, here = here, name = name, island = island, grass = grass}
	return t
end
for _, island in ipairs(T.WorldMap.islands) do
	local x, y = T.mapPoint(island)
	tile(island, 0.06 + x * 0.88, 0.08 + y * 0.8, math.clamp(island.r * 0.95, 56, 110))
end
tile(T.WorldMap.home, 0.08, 0.9, 60)
function S.pickWarp(island, frame)
	local unlocked, requirement = regionState(island.region)
	S.warpPick = island
	chartInfo.Visible = true
	local abs = frame.Position
	chartInfo.Position = UDim2.new(abs.X.Scale, 10, abs.Y.Scale, -20)
	chartInfo.AnchorPoint = Vector2.new(if abs.X.Scale > 0.6 then 1 else 0, 0.5)
	infoTitle.Text = T.escape(island.name)
	if not unlocked then
		infoText.Text = "<font color=\"#FF6B5A\">Locked</font> · " .. T.escape(if requirement ~= "" then "Requires " .. requirement else "Not charted yet")
		infoGo.Text = "Locked"
		T.tone(infoGo, "ghost")
	else
		infoText.Text = if island.travel == "recall" then "Recall charm · instant travel" else "Guided route to the skyway beacon"
		infoGo.Text = if island.travel == "recall" then "Travel" else "Guide me"
		T.tone(infoGo, "primary")
	end
	infoGo:SetAttribute("Locked", not unlocked)
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
	chart.Visible = false
end)
local function refreshChart()
	local here = player:GetAttribute("IsleRegionHere")
	local L = layout()
	chart.Size = UDim2.new(1, -16, 1, -16)
	chartHint.Visible = not L.tiny
	for id, t in pairs(S.tiles) do
		local unlocked = regionState(t.island.region)
		t.lock.Visible = not unlocked
		t.warp.Visible = unlocked
		t.warp.Size = UDim2.fromOffset(if Input.TouchEnabled then 44 else 30, if Input.TouchEnabled then 44 else 30)
		t.grass.BackgroundTransparency = if unlocked then 0 else 0.45
		t.name.TextColor3 = if unlocked then C.text else C.dim
		t.here.Visible = here ~= nil and (here == t.island.region and (id == t.island.region or (id == "Hub" and here == "Hub")))
		t.name.TextSize = if L.short then 10 else 12
		t.name.Visible = not L.tiny or unlocked
	end
end
local function setChart(open)
	chart.Visible = open
	chartInfo.Visible = false
	if open then refreshChart(); setOpen(S.pinned and S.open) end
end
S.setChart = setChart
chartClose.Activated:Connect(function() setChart(false) end)

------------------------------------------------------------------------------
-- Wiring
------------------------------------------------------------------------------
local function accept(snap)
	if type(snap) ~= "table" or type(snap.items) ~= "table" then return end
	S.snap = snap
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
	if key == Enum.KeyCode.E or key == Enum.KeyCode.Tab then setOpen(not S.open)
	elseif key == Enum.KeyCode.Escape then hideMenu(); setChart(false)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 and menu.Visible then
		task.defer(function() if menu.Visible and S.menuFor and not S.confirm then hideMenu() end end)
	end
end)
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if S.open then S.refresh() end end)
player:GetAttributeChangedSignal("IsleSettingPinSatchel"):Connect(function()
	S.pinned = player:GetAttribute("IsleSettingPinSatchel") == true
	if S.pinned and not layout().short then setOpen(true) end
end)
actions:Fire("snapshot")
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
