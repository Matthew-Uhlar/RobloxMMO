local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Input = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer

local function make(class, parent, properties)
	local object = Instance.new(class)
	for key, value in pairs(properties or {}) do
		object[key] = value
	end
	object.Parent = parent
	return object
end
local function rgb(hex)
	return Color3.fromHex(hex)
end
local ink, deep, slate = rgb("102733"), rgb("091923"), rgb("244857")
local ivory, muted, mint, gold = rgb("FFF4D9"), rgb("BECECA"), rgb("9EE7D2"), rgb("F9CC77")
local clothTexture,clothContent
local materials=ReplicatedStorage:FindFirstChild("MaterialArt")
if materials then
	local ok,data=pcall(require,materials)
	if ok and type(data)=="table" then
		if type(data.gui)=="string" and data.gui~="" then clothTexture=data.gui end
		if type(data.getGuiContent)=="function" then
			local ready,content=pcall(data.getGuiContent)
			if ready then clothContent=content end
		end
	end
end
local function panel(parent, position, size, color)
	local textured=(clothContent or clothTexture) and (color==ink or color==deep or color==slate) and (size.X.Scale>0 or size.X.Offset>=32) and (size.Y.Scale>0 or size.Y.Offset>=28)
	local properties={Name="Frame",Position=position,Size=size,BackgroundColor3=color,BorderSizePixel=0}
	if textured then
		if clothContent then properties.ImageContent=clothContent else properties.Image=clothTexture end
		properties.ImageTransparency=.91
		properties.ScaleType=Enum.ScaleType.Tile
		properties.TileSize=UDim2.fromOffset(128,128)
	end
	return make(textured and "ImageLabel" or "Frame",parent,properties)
end
local function garment(object)
	if not clothTexture and not clothContent then return end
	local fabric=make("ImageLabel",object,{Name="WovenSurface",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ImageTransparency=.95,ScaleType=Enum.ScaleType.Tile,TileSize=UDim2.fromOffset(128,128),Active=false,Selectable=false})
	if clothContent then fabric.ImageContent=clothContent else fabric.Image=clothTexture end
	make("UICorner",fabric,{CornerRadius=UDim.new(0,8)})
end
local function rounded(object, radius, edge)
	make("UICorner", object, { CornerRadius = UDim.new(0, radius) })
	if edge then
		make("UIStroke", object, { Color = edge, Transparency = 0.32, Thickness = 1 })
	end
end
local function label(parent, value, x, y, w, h, font, size, color)
	return make("TextLabel", parent, {
		Text = value,
		Position = x and UDim2.fromOffset(x, y) or UDim2.new(),
		Size = UDim2.new(w.Scale, w.Offset, 0, h),
		BackgroundTransparency = 1,
		Font = font,
		TextSize = size,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
end
local full, bold, book, regular = UDim.new(1, 0), Enum.Font.GothamBold, Enum.Font.Antique, Enum.Font.Gotham
local function controlEngraving(parent,caption)
	local emblem=make("Frame",parent,{Name="ControlEngraving",Position=UDim2.new(1,-17,0,3),Size=UDim2.fromOffset(12,12),BackgroundTransparency=1,Active=false})
	local function mark(x,y,w,h,angle)
		local part=make("Frame",emblem,{Position=UDim2.fromScale(x,y),Size=UDim2.fromScale(w,h),AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=gold,BackgroundTransparency=.18,BorderSizePixel=0,Rotation=angle or 0,Active=false})
		return part
	end
	if caption=="Craft" or caption=="Build" or caption=="Upgrade" or caption=="Forge" then
		mark(.45,.6,.15,.7,-35);mark(.65,.3,.6,.22,-35)
	elseif caption=="Collect" or caption=="Claim" or caption=="Deposit" or caption=="Withdraw" or caption=="Buy" or caption=="Sell all" then
		local coin=mark(.5,.5,.65,.65,0);make("UICorner",coin,{CornerRadius=UDim.new(1,0)});mark(.5,.5,.1,.42,0).BackgroundColor3=deep
	elseif caption=="Confirm" or caption=="Accept" then
		mark(.32,.6,.15,.4,-40);mark(.62,.45,.15,.75,40)
	elseif caption=="Cancel" or caption=="Close" then
		mark(.5,.5,.12,.8,45);mark(.5,.5,.12,.8,-45)
	elseif caption=="Feed" or caption=="Eat" or caption=="Drink" then
		mark(.5,.5,.45,.65,35);mark(.5,.5,.07,.8,35).BackgroundColor3=deep
	else
		mark(.5,.5,.5,.5,45);mark(.5,.5,.18,.18,45).BackgroundColor3=deep
	end
end
local function button(parent, caption, pos, dim, action)
	local b = make("TextButton", parent, {
		Name = caption:gsub("[^%w]", "").."Button",
		Text = caption,
		Position = pos,
		Size = dim,
		BackgroundColor3 = slate,
		TextColor3 = ivory,
		TextSize = 14,
		Font = bold,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Selectable = true,
	})
	rounded(b, 8, gold)
	garment(b)
	controlEngraving(b,caption)
	make("UIGradient", b, {Color=ColorSequence.new(Color3.new(1,1,1),rgb("A6C8C9")),Rotation=90})
	local pressScale=make("UIScale",b,{Scale=1})
	b.MouseButton1Down:Connect(function() TweenService:Create(pressScale,TweenInfo.new(.08),{Scale=.96}):Play() end)
	b.MouseButton1Up:Connect(function() TweenService:Create(pressScale,TweenInfo.new(.12),{Scale=1}):Play() end)
	b.MouseLeave:Connect(function() pressScale.Scale=1 end)
	b.Activated:Connect(action)
	return b
end
local gui = make(
	"ScreenGui",
	player:WaitForChild("PlayerGui"),
	{ Name = "AetherAtlas", ResetOnSpawn = false, DisplayOrder = 8, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }
)
local function compass(parent, x, y, size)
	local badge = panel(parent, UDim2.fromOffset(x, y), UDim2.fromOffset(size, size), deep)
	rounded(badge, size, gold)
	for _, angle in ipairs({ 45, 135 }) do
		local blade = panel(badge, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.08, 0.81), mint)
		blade.AnchorPoint = Vector2.new(0.5, 0.5)
		blade.Rotation = angle
	end
	for _, angle in ipairs({ 0, 90 }) do
		local blade = panel(badge, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.10, 0.88), gold)
		blade.AnchorPoint = Vector2.new(0.5, 0.5)
		blade.Rotation = angle
	end
	local core = panel(badge, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.24, 0.24), ivory)
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Rotation = 45
end
-- Original prop masters supply item art; no uploaded asset IDs are required.
local artCatalog
local catalogModule=ReplicatedStorage:WaitForChild("AetherArt",10)
if catalogModule then
	local ok,result=pcall(require,catalogModule)
	if ok then artCatalog=result end
end
local artTemplates={}
local thumbnailCount=0
local function iconWedge(parent,a,b,c,color)
	local ab,ac,bc=b-a,c-a,c-b
	if ab.Magnitude>ac.Magnitude and ab.Magnitude>bc.Magnitude then a,c=c,a elseif ac.Magnitude>ab.Magnitude and ac.Magnitude>bc.Magnitude then a,b=b,a end
	ab,ac,bc=b-a,c-a,c-b
	local normal=ac:Cross(ab)
	if normal.Magnitude<.0001 then return end
	local right,back=normal.Unit,bc.Unit
	local up=back:Cross(right).Unit
	local height=math.abs(ab:Dot(up))
	local function half(mid,x,z,width)
		if width<.001 then return end
		make("WedgePart",parent,{Anchored=true,CanCollide=false,CanTouch=false,CanQuery=false,CastShadow=false,Color=color,Material=Enum.Material.SmoothPlastic,Size=Vector3.new(.025,height,width),CFrame=CFrame.fromMatrix(mid,x,up,z)})
	end
	half((a+b)/2,right,back,math.abs(ab:Dot(back)))
	half((a+c)/2,-right,-back,math.abs(ac:Dot(back)))
end
local function artTemplate(name)
	if artTemplates[name] then return artTemplates[name] end
	local data=artCatalog and artCatalog.shapes[name]
	if not data then return nil end
	local model=Instance.new("Model")
	model.Name=name
	for _,face in ipairs(data.faces) do
		iconWedge(model,Vector3.new(table.unpack(data.vertices[face[1]])),Vector3.new(table.unpack(data.vertices[face[2]])),Vector3.new(table.unpack(data.vertices[face[3]])),rgb(artCatalog.palette[face[4]]))
	end
	artTemplates[name]=model
	return model
end
local function motif(parent,kind,size)
	local frame=panel(parent,UDim2.new(),UDim2.fromOffset(size,size),deep)
	rounded(frame,9,slate)
	local function stroke(x,y,w,h,angle,color)
		local mark=panel(frame,UDim2.fromScale(x,y),UDim2.fromScale(w,h),color or gold)
		mark.AnchorPoint=Vector2.new(.5,.5)
		mark.Rotation=angle or 0
		return mark
	end
	if kind=="Ledger" then
		for i=1,3 do local coin=stroke(.33+i*.1,.7-i*.13,.44,.17,0,i==3 and gold or mint);rounded(coin,size) end
	elseif kind=="Workshop" then
		stroke(.48,.55,.10,.62,-32,mint);stroke(.56,.31,.55,.16,-32,gold)
	elseif kind=="Satchel" then
		local bag=stroke(.5,.58,.52,.48,0,mint);rounded(bag,4)
		local loop=stroke(.5,.27,.28,.22,0,gold);rounded(loop,5)
		stroke(.5,.55,.12,.2,0,deep)
	elseif kind=="Ration" then
		local parcel=stroke(.5,.55,.58,.48,-12,mint);rounded(parcel,4)
		stroke(.5,.55,.10,.52,-12,gold);stroke(.5,.55,.62,.09,-12,gold)
		stroke(.48,.24,.22,.32,38,mint)
	elseif kind=="Co-op" then
		for _,x in ipairs({.3,.7}) do local gem=stroke(x,.35,.2,.2,45,mint);rounded(gem,3);stroke(x,.64,.24,.27,0,gold) end
		stroke(.5,.76,.63,.055,0,mint)
	else
		stroke(.5,.5,.13,.68,35,mint);stroke(.5,.5,.13,.68,-55,gold)
		stroke(.5,.5,.24,.24,45,ivory)
	end
	return frame
end
local function thumbnail(parent,name,size)
	local template=artTemplate(name)
	if not template or thumbnailCount>=18 then return motif(parent,"Journal",size) end
	thumbnailCount+=1
	local view=make("ViewportFrame",parent,{Size=UDim2.fromOffset(size,size),BackgroundColor3=deep,BorderSizePixel=0,Ambient=rgb("B5D8DD"),LightColor=rgb("FFE1A6"),LightDirection=Vector3.new(-1,-1,-2)})
	rounded(view,9,slate)
	local model=template:Clone()
	model.Parent=view
	local cf,dimensions=model:GetBoundingBox()
	local radius=math.max(dimensions.X,dimensions.Y,dimensions.Z)
	local camera=make("Camera",view,{FieldOfView=34,CFrame=CFrame.lookAt(cf.Position+Vector3.new(.7,.38,-1).Unit*radius*2,cf.Position)})
	view.CurrentCamera=camera
	return view
end
local iconMappings={
	{"ReinforcedPickaxe","Pickaxe"},{"Pickaxe","Pickaxe"},{"Skyplate","Skyplate"},{"AetherIngot","AetherIngot"},{"AlloyIngot","AlloyIngot"},
	{"Stormblade","Blade"},{"Blade","Blade"},{"Tonic","Tonic"},{"Timber","TimberBundle"},{"Woodcutting","WindpineCrown"},{"Mining","AetherCrystal"},
	{"Aetherite","AetherCrystal"},{"Ore","AetherCrystal"},{"Shard","AetherCrystal"},{"Stormglass","AetherCrystal"},{"Herb","Moonbloom"},{"Garden","Moonbloom"},
	{"Farming","Moonbloom"},{"Fish","Fish"},{"worker","Surveyor"},{"Worker","Surveyor"},{"Lantern","Lantern"},{"Vault","VaultChest"},{"Purse","VaultChest"},
	{"homestead","FloatingIslet"},{"Deck","FloatingIslet"},{"Smithing","AlloyIngot"},{"Combat","Blade"},{"Enchant","AetherCrystal"},{"Alchemy","Tonic"},
}
local function titleArt(parent,title,size,page)
	if title:find("ExpeditionRation",1,true) then return motif(parent,"Ration",size) end
	for _,mapping in ipairs(iconMappings) do if title:find(mapping[1],1,true) then return thumbnail(parent,mapping[2],size) end end
	return motif(parent,page,size)
end
local hud = panel(gui, UDim2.fromOffset(10, 8), UDim2.new(1, -20, 0, 88), ink)
make("UISizeConstraint", hud, { MaxSize = Vector2.new(305, 88) })
rounded(hud, 9, slate)
compass(hud, 10, 10, 37)
label(hud, "A E T H E R   I S L E S", 55, 7, UDim.new(1, -120), 20, bold, 11, mint)
local purse = label(hud, "Opening ledger…", 55, 26, UDim.new(1, -130), 22, regular, 13, ivory)
local instruction = label(hud, "Charting the islands…", 12, 53, UDim.new(1, -24), 28, bold, 13, gold)
local openAtlas
local opener = button(hud, "Atlas", UDim2.new(1, -67, 0, 8), UDim2.fromOffset(58, 42), function()
	openAtlas()
end)
local shade = make("TextButton", gui, {
	Text = "",
	AutoButtonColor = false,
	BackgroundColor3 = deep,
	BackgroundTransparency = 0.32,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	Selectable = false,
})
local atlas = panel(gui, UDim2.fromScale(0.5, 0.5), UDim2.new(1, -20, 1, -20), ink)
atlas.Name = "Atlas"
atlas.Active = true
atlas.AnchorPoint = Vector2.new(0.5, 0.5)
atlas.Visible = false
rounded(atlas, 12, gold)
make("UISizeConstraint", atlas, { MaxSize = Vector2.new(760, 690) })
local head = panel(atlas, UDim2.new(), UDim2.new(1, 0, 0, 88), slate)
rounded(head, 12)
make("UIGradient", head, { Color = ColorSequence.new(rgb("36706F"), ink), Rotation = 12 })
compass(head, 13, 10, 43)
label(head, "CARTOGRAPHERS' GUILD", 68, 6, UDim.new(1, -138), 19, bold, 10, mint)
label(head, "Voyager’s Atlas", 67, 24, UDim.new(1, -138), 33, book, 27, ivory)
local mastheadCaption=label(head,"CHART YOUR COURSE  /  BUILD YOUR LEGACY",16,61,UDim.new(1,-32),17,bold,10,gold)
local edge=panel(head,UDim2.new(0,14,1,-3),UDim2.new(1,-28,0,1),gold)
edge.BackgroundTransparency=.5
local function closeAtlas()
	atlas.Visible = false
	shade.Visible = false
	hud.Visible = true
	if Input.GamepadEnabled then
		GuiService.SelectedObject = opener
	end
end
button(head, "Close", UDim2.new(1, -64, 0, 10), UDim2.fromOffset(54, 43), closeAtlas)
shade.Activated:Connect(closeAtlas)
local tabs = panel(atlas, UDim2.fromOffset(10, 96), UDim2.new(1, -20, 0, 56), ink)
tabs.Name = "Tabs"
local scroll = make("ScrollingFrame", atlas, {
	Position = UDim2.fromOffset(12, 160),
	Size = UDim2.new(1, -24, 1, -197),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = mint,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
})
make("UIListLayout", scroll, { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) })
local footer = label(atlas, "AETHER ISLES     /     FIELD EDITION", 14, 0, UDim.new(1, -28), 22, bold, 10, muted)
footer.Position = UDim2.new(0, 14, 1, -27)
local notice = label(gui, "", 0, 0, UDim.new(0.92, 0), 38, bold, 13, ivory)
notice.AnchorPoint = Vector2.new(0.5, 1)
notice.Position = UDim2.new(0.5, 0, 1, -6)
notice.TextXAlignment = Enum.TextXAlignment.Center
notice.TextWrapped = true
notice.BackgroundColor3 = deep
notice.BackgroundTransparency = 0.03
notice.Visible = false
rounded(notice, 8, slate)
garment(notice)
notice.AutomaticSize = Enum.AutomaticSize.Y
notice.TextTruncate = Enum.TextTruncate.None
make("UIPadding", notice, {PaddingTop=UDim.new(0,8),PaddingBottom=UDim.new(0,8),PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,12)})
make("UISizeConstraint", notice, { MaxSize = Vector2.new(560, 180) })
local noticeIndex = 0
local function notify(message)
	if not message or message == "" then
		return
	end
	noticeIndex += 1
	local token = noticeIndex
	notice.Text = message
	notice.Visible = true
	notice.TextTransparency = 0.35
	TweenService:Create(notice, TweenInfo.new(0.16), { TextTransparency = 0 }):Play()
	task.delay(3.6, function()
		if token == noticeIndex then
			notice.Visible = false
		end
	end)
end

local state = {
	quest = nil,
	stats = nil,
	decorations = {},
	items = {},
	levels = {},
	collection = {},
	xp = {},
	coins = 0,
	bank = 0,
	worker = false,
	workerResource = "Ore",
	enchantRank = 0,
	workerReady = 0,
	ironman = false,
	preview = false,
	started = false,
}
local synced = false
local current = "Journal"
local compactAtlas = false
local render, send, sendCoop
local coopState, coopError
local coopPending = false
local coopConfirm = nil
local tabButtons = {}
local order = 0
local function listItem(object)
	order += 1
	object.LayoutOrder = order
	return object
end
local function heading(text)
	local strip=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,29),ink))
	local marker=panel(strip,UDim2.fromOffset(3,11),UDim2.fromOffset(6,6),gold)
	marker.Rotation=45
	label(strip,text,19,2,UDim.new(1,-25),25,bold,11,mint)
end
-- Flexible card copy remains stacked beneath custom item art at phone widths.
local function row(title, detail, tag, callback)
	local box = listItem(panel(scroll, UDim2.new(), UDim2.new(1, -7, 0, 0), deep))
	box.AutomaticSize = Enum.AutomaticSize.Y
	rounded(box, 10, slate)
	make("UIGradient",box,{Color=ColorSequence.new(rgb("FFFFFF"),rgb("B2D0D6")),Rotation=22})
	make("UIPadding", box, {PaddingTop=UDim.new(0,12),PaddingBottom=UDim.new(0,12),PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,12)})
	make("UIListLayout", box, {SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,9)})
	local iconSize=compactAtlas and 40 or 52
	local titleBand=panel(box,UDim2.new(),UDim2.new(1,0,0,iconSize+2),deep)
	titleBand.BackgroundTransparency=1
	titleBand.AutomaticSize=Enum.AutomaticSize.Y
	titleBand.LayoutOrder=1
	titleArt(titleBand,title,iconSize,current)
	local titleLabel = label(titleBand, title, iconSize+12, 1, UDim.new(1,-iconSize-12), iconSize, bold, compactAtlas and 14 or 16, ivory)
	titleLabel.AutomaticSize = Enum.AutomaticSize.Y
	titleLabel.TextWrapped = true
	titleLabel.TextTruncate = Enum.TextTruncate.None
	titleLabel.TextYAlignment=Enum.TextYAlignment.Center
	local sub = label(box, detail, 0, 0, full, 18, regular, compactAtlas and 12 or 13, muted)
	sub.LayoutOrder = 2
	sub.AutomaticSize = Enum.AutomaticSize.Y
	sub.TextWrapped = true
	sub.TextTruncate = Enum.TextTruncate.None
	if tag then
		local actions = panel(box, UDim2.new(), UDim2.new(1,0,0,44), deep)
		actions.BackgroundTransparency=1
		actions.LayoutOrder = 3
		local line=panel(actions,UDim2.new(0,0,.5,0),UDim2.new(1,-120,0,1),slate)
		button(actions, tag, UDim2.new(1,-108,0,0), UDim2.fromOffset(108,44), callback)
	end
end
local function count(map, key)
	return (state[map] and state[map][key]) or 0
end
local function nextGoal()
	if count("items", "Pickaxe") == 0 and count("items", "ReinforcedPickaxe") == 0 then
		if count("items", "Timber") < 2 then
			return "Windpine timber  ·  " .. count("items", "Timber") .. " / 2",
				"Use the windpine prompt on your home island."
		end
		if count("items", "Ore") < 3 then
			return "Brassfall ore  ·  " .. count("items", "Ore") .. " / 3",
				"Take the home portal to Compass Quay. Go east to Brassfall Quarry."
		end
		return "Forge your pickaxe", "Open Workshop and craft the Pickaxe."
	end
	if not state.worker then
		return "Build an island worker", "Save 5 timber and 3 ore, then open Workshop."
	end
	return "Explore the islands", "Train a skill, discover materials or challenge a foe."
end
local confirmIron = false
local function routeChart()
	local chart=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,144),slate))
	rounded(chart,10,gold)
	make("UIGradient",chart,{Color=ColorSequence.new(rgb("34716E"),rgb("112A3A")),Rotation=25})
	label(chart,"THE FIRST CROSSING",12,7,UDim.new(1,-24),19,bold,10,gold)
	local line=panel(chart,UDim2.fromScale(.14,.56),UDim2.fromScale(.72,.012),mint)
	line.BackgroundTransparency=.4
	for i,landmark in ipairs({"Windpine","Compass Quay","Brassfall"}) do
		local x=.16+(i-1)*.34
		local art=thumbnail(chart,({"WindpineCrown","FloatingIslet","AetherCrystal"})[i],60)
		art.AnchorPoint=Vector2.new(.5,0)
		art.Position=UDim2.new(x,0,0,35)
		art.BackgroundTransparency=.35
		local caption=label(chart,landmark,0,0,UDim.new(.32,0),28,bold,11,ivory)
		caption.Position=UDim2.new(x,0,0,105)
		caption.AnchorPoint=Vector2.new(.5,0)
		caption.TextXAlignment=Enum.TextXAlignment.Center
		caption.TextWrapped=true
		caption.TextTruncate=Enum.TextTruncate.None
	end
end
local function drawJournal()
	local goal, detail = nextGoal()
	heading("01    /    NEXT BEARING")
	row(goal, detail)
	routeChart()
	if state.quest then
		row(state.quest.title, state.quest.detail, state.quest.ready and "Claim" or nil, function()
			send("quest")
		end)
	end
	if state.slayer then
		local hunt = state.slayer
		heading("WARDEN    /    HUNT CONTRACTS")
		local reward = hunt.coins .. " coins + " .. hunt.xp .. " Combat XP."
		if hunt.active then
			row("Tier " .. hunt.tier .. " hunt · " .. hunt.progress .. " / " .. hunt.target,
				hunt.ready and ("Hunt complete. " .. reward) or ("Defeat Wardens after accepting this hunt. " .. reward),
				if hunt.ready then "Claim" else nil, function() send("slayerClaim") end)
		else
			row("Tier " .. hunt.tier .. " Warden hunt", "Defeat " .. hunt.target .. " Wardens. " .. reward .. " Higher tiers require longer hunts; tier 3 is repeatable.",
				"Accept", function() send("slayerStart") end)
		end
	end
	if state.regions and #state.regions>0 then
		heading("REGIONS    /    EXPEDITION CHARTERS")
		for _,region in ipairs(state.regions) do
			row(region.name,region.visited and "Survey complete. Return through the Brassfall Quarry transit beacon." or (region.unlocked and "Charter unlocked. Travel from Brassfall Quarry and survey the region." or region.requirement))
		end
	end
	heading("02    /    SKILL RECORD")
	if state.stats then
		row("Vitality & armor", state.stats.maxHealth .. " max health   /   " .. state.stats.defense .. " defense")
	end
	for _, key in ipairs({
		"Mining",
		"Woodcutting",
		"Farming",
		"Fishing",
		"Smithing",
		"Combat",
		"Alchemy",
		"Dungeoneering",
		"Enchanting",
		"Taming",
	}) do
		row(key .. "   ·   Lv. " .. (state.levels[key] or 1), tostring(count("xp", key)) .. " lifetime XP")
	end
	heading("03    /    EXPEDITION RULES")
	if state.ironman then
		row("Ironman", "Player exchange disabled. Warden hunts are solo; Observatory expeditions allow allies.")
	elseif not state.started then
		row(
			"Ironman charter",
			"Permanent trading restriction and solo Warden hunts. Choose before starting progression.",
			confirmIron and "Confirm" or "Review",
			function()
				if confirmIron then
					confirmIron = false
					send("ironman")
				else
					confirmIron = true
					render()
				end
			end
		)
	else
		row("Standard expedition", "Visit Compass Quay to meet other voyagers.")
	end
end
local function drawPack()
	heading("01    /    PROVISIONS")
	local keys = {}
	for key, value in pairs(state.items) do
		if value > 0 then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	if #keys == 0 then
		row("Your satchel is empty", "Use a gathering prompt to collect your first resource.")
	end
	for _, key in ipairs(keys) do
		local consumable=state.consumables and state.consumables[key]
		local detail="Carried in your satchel."
		if consumable then
			detail="Restores up to " .. consumable.healing .. " health."
			if consumable.recovery>0 then detail ..= " Recovery: " .. consumable.recovery .. " seconds between uses." end
			if consumable.readyIn>0 then detail ..= " " .. math.ceil(consumable.readyIn) .. " seconds remaining at last check; use again when recovered." end
		end
		row(key .. "   ×" .. state.items[key],detail,consumable and consumable.action or nil,function() send("heal",key) end)

	end
	heading("02    /    COLLECTION LOG")
	local resources = {}
	for key in pairs(state.collection) do
		table.insert(resources, key)
	end
	table.sort(resources)
	if #resources == 0 then
		row("Uncharted", "Gather materials to record your discoveries.")
	end
	for _, key in ipairs(resources) do
		row(key, tostring(state.collection[key]) .. " gathered across your expedition")
	end
end
local workshopSection="Forge"
local function drawForge()
	heading("01    /    FORGE PATTERNS")
	for _, recipe in ipairs(state.recipes or {}) do
		local name=recipe.id
		local ingredients={}
		local materials={}
		for material in pairs(recipe.costs) do table.insert(materials,material) end
		table.sort(materials)
		for _,material in ipairs(materials) do table.insert(ingredients,recipe.costs[material] .. " " .. material .. " (" .. count("items",material) .. " held)") end
		local requirements={recipe.skill .. " " .. recipe.level}
		local gates={}
		for material in pairs(recipe.collection) do table.insert(gates,material) end
		table.sort(gates)
		for _,material in ipairs(gates) do table.insert(requirements,recipe.collection[material] .. " lifetime " .. material) end
		local detail=recipe.description .. ". " .. table.concat(ingredients, " + ") .. ". Requires " .. table.concat(requirements,", ") .. ". +" .. recipe.xp .. " " .. recipe.skill .. " XP."
		local owned=not recipe.repeatable and count("items",name)>0
		row(name,detail,if owned then nil else (recipe.unlocked and "Craft" or "Locked"),function()
			if recipe.unlocked then send("craft",name) else notify("Requires " .. table.concat(requirements,", ") .. ".") end
		end)
	end
	local rank = state.enchantRank or 0
	row(
		"Blade enchantment · Rank " .. rank .. " / 3",
		rank >= 3 and "Fully enchanted · +9 Warden damage" or "2 shard + 4 herb per rank. Needs a Blade or Stormblade.",
		if rank >= 3 then nil else "Enchant",
		function()
			send("enchant")
		end
	)
	row("Aetherite equipment", "Train Mining to 3 to work the Aetherite seam. Refine Alloy Ingots to reach Smithing 3, then forge Aether Ingots, a reinforced pickaxe and Skyplate.")
end
local function drawWorkers()
	heading("02    /    ISLAND INDUSTRY")
	row("Worker fleet", "Up to three workers gather independently, including while away. Changing assignments collects completed output and restarts the current cycle.")
	local workers = state.workers or {}
	for slot = 1, 3 do
		local worker = workers[slot]
		if worker then
			local slotId = tostring(slot)
			row("Worker " .. slot .. " · " .. worker.resource .. " · Tier " .. worker.tier,
				tostring(worker.ready) .. " ready at last check. One resource every " .. worker.interval .. " seconds; stores " .. worker.capacity .. ".",
				"Collect", function() send("workerClaim", slotId) end)
			if worker.tier < 3 then
				local nextTier = worker.tier + 1
				row("Upgrade worker " .. slot, (nextTier*5) .. " timber + " .. (nextTier*3) .. " ore. Completed output collected; a faster cycle starts with more storage.",
					"Upgrade", function() send("workerUpgrade", slotId) end)
			end
			for _, resource in ipairs({"Ore", "Timber", "Herb", "Fish"}) do
				local selected = resource == worker.resource
				row("Worker " .. slot .. " / " .. resource, selected and "Current assignment" or "Assign this worker to gather " .. resource .. ".",
					if selected then nil else "Assign", function() send("workerAssign", slotId .. ":" .. resource) end)
			end
		elseif slot == #workers + 1 then
			row("Build worker " .. slot, (5*slot) .. " timber + " .. (3*slot) .. " ore", "Build", function()
				send("workerBuild", tostring(slot))
			end)
		end
	end
end
local function drawHome()
	heading("03    /    HOME IMPROVEMENTS")
	for _, plan in ipairs({
		{ "Lanterns", "5 timber" },
		{ "Garden", "3 herb + 3 timber" },
		{
			"Deck",
			"10 timber + 5 ore",
		},
	}) do
		local name = plan[1]
		local built = state.decorations and state.decorations[name]
		row(name, built and "Built on your home island" or plan[2], if built then nil else "Build", function()
			send("decorate", name)
		end)
	end
	local bond = state.companionBond or 0
	heading("COMPANION    /    TAMING")
	row(
		"Companion bond · " .. bond .. " / 5",
		bond >= 5 and "Fully bonded · +10 maximum health" or "Feed 2 Fish for 20 Taming XP and +2 maximum health.",
		bond < 5 and "Feed" or nil,
		function()
			send("feed")
		end
	)
end
local function drawCraft()
	local sections=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,44),ink))
	for index,name in ipairs({"Forge","Workers","Home"}) do
		local choice=button(sections,name,UDim2.new((index-1)/3,0,0,0),UDim2.new(1/3,-4,0,44),function()
			workshopSection=name
			scroll.CanvasPosition=Vector2.zero
			render()
		end)
		choice.BackgroundColor3=name==workshopSection and mint or slate
		choice.TextColor3=name==workshopSection and deep or ivory
	end
	if workshopSection=="Forge" then drawForge() elseif workshopSection=="Workers" then drawWorkers() else drawHome() end
end
local function drawTrade()
	heading("01    /    BANK LEDGER")
	row("Purse   ·   " .. (state.coins or 0), "Transfer carried coins into the vault.", "Deposit", function()
		send("deposit")
	end)
	row("Vault   ·   " .. (state.bank or 0), "Return stored coins to your purse.", "Withdraw", function()
		send("withdraw")
	end)
	heading("02    /    MERCHANT")
	row("Sell raw materials", "Sell all eligible materials in your satchel.", "Sell all", function()
		send("sell")
	end)
	heading("03    /    PLAYER EXCHANGE")
	if state.ironman then
		row("Sealed charter", "Player trading is unavailable in Ironman.")
		return
	end
	row("Commodity counter", "Each order trades 3 units. Sellers receive proceeds after a sale.")
	for _, lot in ipairs({ { "Ore", 15 }, { "Timber", 12 }, { "Herb", 9 }, { "Fish", 18 } }) do
		local item = lot[1]
		local card = listItem(panel(scroll, UDim2.new(), UDim2.new(1, -7, 0, 116), deep))
		rounded(card, 7, slate)
		local art=titleArt(card,item,44,"Ledger")
		art.Position=UDim2.fromOffset(8,7)
		local lotTitle=label(card,item .. " ×3 / " .. lot[2] .. " coins",62,7,UDim.new(1,-70),44,bold,14,ivory)
		lotTitle.TextWrapped=true
		lotTitle.TextTruncate=Enum.TextTruncate.None
		for index, command in ipairs({
			{ "Buy", "buy" },
			{ "List", "list" },
			{ "Cancel", "cancel" },
			{ "Collect", "proceeds" },
		}) do
			local verb = command[2]
			button(card, command[1], UDim2.new((index - 1) / 4, 2, 0, 64), UDim2.new(1 / 4, -4, 0, 43), function()
				send(verb, item)
			end)
		end
	end
end
local function drawCoop()
	heading("CO-OP    /    SHARED HOMESTEAD")
	if coopPending then
		row("Opening the shared ledger…", "Please wait for the current request to finish.")
	end
	if coopError then row("Shared ledger unavailable", coopError, "Retry", function() sendCoop("state") end) end
	if not coopState then
		if not coopPending and not coopError then row("Your shared homestead", "Open the co-op ledger to view your membership and invitations.", "Refresh", function() sendCoop("state") end) end
		return
	end
	local group = coopState
	if group.preview then row("Studio practice", "This co-op ledger is temporary and will not save.") end
	if group.pendingGroup then
		row("Membership needs recovery", "Retry the membership you already chose. This completes the same permanent crew membership.", "Retry", function()
			if group.pendingGroup == tostring(player.UserId) then sendCoop("create") else sendCoop("accept",group.pendingGroup) end
		end)
		return
	end
	if not group.groupId then
		row("A permanent crew", "Create or join a crew of up to four voyagers in the same mode. Membership is permanent in this version: there is no leave or kick option. Your personal island and inventory stay separate.")
		local createConfirm = coopConfirm == "create"
		row(createConfirm and "Confirm permanent membership" or "Found a shared homestead",
			createConfirm and "Creating this crew permanently makes you its founder. There is no leave or kick option. Confirm only if you want this crew." or "Start a crew, then invite players from this server.",
			createConfirm and "Confirm" or "Create", function()
				if coopConfirm == "create" then coopConfirm=nil; sendCoop("create") else coopConfirm="create"; render() end
			end)
		heading("INVITATIONS")
		if #(group.invites or {}) == 0 then row("No invitations", "Ask a crew founder in this server to invite you, then refresh.") end
		for _, invite in ipairs(group.invites or {}) do
			local groupId = invite.groupId
			local confirming = coopConfirm == groupId
			row("Join " .. invite.name .. "’s crew", confirming and "This membership is permanent. You cannot leave or be kicked in this version. Confirm to join this crew." or ((invite.ironman and "Ironman" or "Standard") .. " crew invitation. Review before joining."),
				confirming and "Confirm" or "Review", function()
					if coopConfirm == groupId then coopConfirm=nil; sendCoop("accept",groupId) else coopConfirm=groupId; render() end
				end)
		end
	else
		row((group.ironman and "Ironman" or "Standard") .. " crew · " .. #(group.members or {}) .. " / 4", "Travel to your shared homestead from Compass Quay. Membership is permanent; leaving and kicking are not available.")
		heading("CREW ROSTER")
		local memberIds = {}
		for _, member in ipairs(group.members or {}) do
			memberIds[member.userId] = true
			row(member.name, member.userId == group.owner and "Founder" or "Crew member")
		end
		if group.owner == player.UserId and #(group.members or {}) < 4 then
			heading("INVITE FROM THIS SERVER")
			local candidates = 0
			for _, candidate in ipairs(Players:GetPlayers()) do
				if not memberIds[candidate.UserId] then
					candidates += 1
					local userId = tostring(candidate.UserId)
					row(candidate.DisplayName .. " (@" .. candidate.Name .. ")", "The server checks that this player has the same mode and can join.", "Invite", function() sendCoop("invite",userId) end)
				end
			end
			if candidates == 0 then row("No other voyagers here", "Invite friends after they join this server.") end
		end
		heading("SHARED SUPPLIES")
		row("Crew stores", "Gather at shared-island prompts to fill these stores. Supplies stay with the crew; they are separate from your satchel and cannot be withdrawn.")
		for _, resource in ipairs({"Timber","Ore","Herb"}) do row(resource, tostring((group.supplies or {})[resource] or 0) .. " in shared stores") end
		heading("SHARED IMPROVEMENTS")
		for _, plan in ipairs({{"Garden","3 herb + 3 timber"},{"Lanterns","5 timber"},{"Deck","10 timber + 5 ore"}}) do
			local name = plan[1]
			local built = (group.decorations or {})[name]
			row(name, built and "Built on the shared homestead" or (plan[2] .. " from shared stores"), if built then nil else "Build", function() sendCoop("build",name) end)
		end
	end
	if coopConfirm then row("Keep deciding", "Cancel this confirmation without changing your membership.", "Cancel", function() coopConfirm=nil; render() end) end
	row("Shared ledger", "Refresh after crew activity or to check new invitations.", "Refresh", function() sendCoop("state") end)
end
local pages = { Journal = drawJournal, Satchel = drawPack, Workshop = drawCraft, Ledger = drawTrade, ["Co-op"] = drawCoop }
render = function()
	compactAtlas=atlas.AbsoluteSize.X<480 or atlas.AbsoluteSize.Y<500
	head.Size=UDim2.new(1,0,0,compactAtlas and 64 or 88)
	mastheadCaption.Visible=not compactAtlas
	tabs.Position=UDim2.fromOffset(10,compactAtlas and 70 or 96)
	tabs.Size=UDim2.new(1,-20,0,compactAtlas and 44 or 56)
	local contentTop=compactAtlas and 122 or 160
	scroll.Position=UDim2.fromOffset(12,contentTop)
	scroll.Size=UDim2.new(1,-24,1,-contentTop-37)
	purse.Text = synced and ((state.ironman and "Ironman" or "Voyager") .. "   ·   " .. (state.coins or 0) .. " coins")
		or "Opening ledger…"
	instruction.Text = synced and nextGoal() or "Charting the islands…"
	if not atlas.Visible then
		return
	end
	local restoreFocus = Input.GamepadEnabled and GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(scroll)
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	order = 0
	thumbnailCount = 0
	for name, b in pairs(tabButtons) do
		b.BackgroundColor3 = name == current and mint or slate
		b.TextColor3 = name == current and deep or ivory
		local caption=b:FindFirstChild("TabCaption")
		if caption then caption.TextColor3=name==current and deep or ivory;caption.Position=UDim2.fromOffset(2,compactAtlas and 22 or 30) end
		local icon=b:FindFirstChild("TabIcon")
		if icon then icon.Size=UDim2.fromOffset(compactAtlas and 18 or 23,compactAtlas and 18 or 23);icon.Position=UDim2.new(.5,compactAtlas and -9 or -11,0,compactAtlas and 2 or 4) end
	end
	if synced then
		pages[current]()
	else
		heading("OPENING YOUR LEDGER…")
	end
	if restoreFocus then GuiService.SelectedObject = tabButtons[current] end
	footer.Text = state.preview and "STUDIO PRACTICE     /     PROGRESS IS TEMPORARY"
		or "AETHER ISLES     /     FIELD EDITION"
end
for i, name in ipairs({ "Journal", "Satchel", "Workshop", "Ledger", "Co-op" }) do
	local b = button(tabs, name, UDim2.new((i - 1) / 5, 0, 0, 0), UDim2.new(0.2, -3, 1, 0), function()
		current = name
		confirmIron = false
		coopConfirm = nil
		scroll.CanvasPosition = Vector2.zero
		render()
		if name == "Co-op" and sendCoop then sendCoop("state") end
	end)
	b.Text = ""
	local engraving=b:FindFirstChild("ControlEngraving")
	if engraving then engraving:Destroy() end
	local tabIcon=motif(b,name,23)
	tabIcon.Name="TabIcon"
	tabIcon.Position=UDim2.new(.5,-11,0,4)
	tabIcon.BackgroundTransparency=1
	local tabCaption=label(b,name,2,30,UDim.new(1,-4),20,bold,11,ivory)
	tabCaption.Name="TabCaption"
	tabCaption.TextXAlignment=Enum.TextXAlignment.Center
	tabCaption.TextScaled=true
	make("UITextSizeConstraint",tabCaption,{MinTextSize=9,MaxTextSize=12})
	b.TextSize = 13
	b.TextScaled = true
	make("UITextSizeConstraint", b, {MinTextSize=10,MaxTextSize=13})
	tabButtons[name] = b
end
atlas:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if atlas.Visible then render() end end)
openAtlas = function()
	atlas.Visible = true
	atlas.Position=UDim2.new(.5,0,.5,8)
	TweenService:Create(atlas,TweenInfo.new(.18,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.fromScale(.5,.5)}):Play()
	hud.Visible = false
	shade.Visible = true
	render()
	if send then send("state") end
	if current == "Co-op" and sendCoop then sendCoop("state") end
	if Input.GamepadEnabled then
		GuiService.SelectedObject = tabButtons[current]
	end
end
Input.InputBegan:Connect(function(input, used)
	if used then
		return
	end
	if input.KeyCode == Enum.KeyCode.J or input.KeyCode == Enum.KeyCode.ButtonY then
		if atlas.Visible then
			closeAtlas()
		else
			openAtlas()
		end
	elseif input.KeyCode == Enum.KeyCode.ButtonB and atlas.Visible then
		closeAtlas()
	end
end)
local remote = ReplicatedStorage:WaitForChild("IsleAction")
local updates = ReplicatedStorage:WaitForChild("IsleUpdate")
local function accept(data)
	if type(data) ~= "table" or type(data.items) ~= "table" then
		if type(data) == "table" then
			notify(data.message)
		end
		return false
	end
	state = data
	synced = true
	render()
	notify(data.message)
	return true
end
local pending = false
send = function(action, item)
	if pending then
		return
	end
	pending = true
	local ok, result = pcall(function()
		return remote:InvokeServer(action, item)
	end)
	pending = false
	if ok then
		accept(result)
	else
		notify("Your ledger could not be reached. Try again.")
	end
end
local function acceptCoop(result)
	if type(result) ~= "table" or type(result.members) ~= "table" then return false end
	coopState = result
	coopError = nil
	if result.groupId then coopConfirm = nil end
	render()
	notify(result.message)
	return true
end
sendCoop = function(verb, item)
	if coopPending then return end
	local remoteCoop = ReplicatedStorage:FindFirstChild("IsleCoopAction")
	if not remoteCoop then
		coopError = "The shared ledger is still starting. Try again in a moment."
		render()
		return
	end
	coopPending = true
	coopError = nil
	render()
	local ok, result = pcall(function() return remoteCoop:InvokeServer(verb,item) end)
	coopPending = false
	if not (ok and acceptCoop(result)) then
		coopError = if ok and type(result) == "table" and type(result.message) == "string" then result.message else "The shared ledger could not be reached. Refresh before trying again."
	end
	render()
end
task.spawn(function()
	ReplicatedStorage:WaitForChild("IsleCoopUpdate").OnClientEvent:Connect(acceptCoop)
end)
updates.OnClientEvent:Connect(accept)
while not synced do
	send("state")
	if not synced then
		task.wait(2)
	end
end

