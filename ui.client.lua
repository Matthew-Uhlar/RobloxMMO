local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Input = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer

local function make(class, parent, properties)
	local object = Instance.new(class)
	-- Every stroke in the atlas is a rim. The Contextual default would outline the
	-- TEXT of a TextButton/TextLabel instead (and draw nothing on blank tiles,
	-- hiding selection rims), so strokes default to Border.
	if class == "UIStroke" then object.ApplyStrokeMode = Enum.ApplyStrokeMode.Border end
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
local ember, track = rgb("E8806A"), rgb("0B1E29")
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
	if not clothTexture and not clothContent then
		-- A small original stitch-and-diamond border needs no image allocation.
		local trim=make("Frame",object,{Name="WovenSurface",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Active=false,Selectable=false})
		for _,side in ipairs({0,1}) do
			for index=1,3 do
				make("Frame",trim,{Position=UDim2.new(side,side==0 and (5+index*5) or (-5-index*5),1,-5),Size=UDim2.fromOffset(3,1),BackgroundColor3=gold,BackgroundTransparency=.45,BorderSizePixel=0,Active=false})
			end
		end
		return
	end
	local fabric=make("ImageLabel",object,{Name="WovenSurface",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ImageTransparency=.95,ScaleType=Enum.ScaleType.Tile,TileSize=UDim2.fromOffset(128,128),Active=false,Selectable=false})
	if clothContent then fabric.ImageContent=clothContent else fabric.Image=clothTexture end
	make("UICorner",fabric,{CornerRadius=UDim.new(0,8)})
end
local function rounded(object, radius, edge)
	make("UICorner", object, { CornerRadius = UDim.new(0, radius) })
	if edge then
		local rim=make("UIStroke", object, { Color = edge, Transparency = 0.32, Thickness = 1 })
		if not clothContent and not clothTexture then make("UIGradient",rim,{Color=ColorSequence.new(gold,slate),Rotation=35}) end
	end
end
local compactAtlas = false
local function label(parent, value, x, y, w, h, font, size, color)
	-- Readability floor: 12px on phones (compact atlas), 10px elsewhere.
	size = math.max(size, compactAtlas and 12 or 10)
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
	if caption=="Craft" or caption=="Build" or caption=="Upgrade" or caption=="Forge" or caption=="Enchant" then
		mark(.45,.6,.15,.7,-35);mark(.65,.3,.6,.22,-35)
	elseif caption=="Collect" or caption=="Claim" or caption=="Deposit" or caption=="Withdraw" or caption=="Buy" or caption=="Sell all" or caption=="Sell" or caption=="Begin" then
		local coin=mark(.5,.5,.65,.65,0);make("UICorner",coin,{CornerRadius=UDim.new(1,0)});mark(.5,.5,.1,.42,0).BackgroundColor3=deep
	elseif caption=="Confirm" or caption=="Accept" or caption=="Equip" or caption=="Summon" or caption=="Adopt" or caption=="Add" then
		mark(.32,.6,.15,.4,-40);mark(.62,.45,.15,.75,40)
	elseif caption=="Cancel" or caption=="Close" or caption=="Unequip" or caption=="Dismiss" or caption=="Remove" or caption=="Abandon" then
		mark(.5,.5,.12,.8,45);mark(.5,.5,.12,.8,-45)
	elseif caption=="Feed" or caption=="Eat" or caption=="Drink" then
		mark(.5,.5,.45,.65,35);mark(.5,.5,.07,.8,35).BackgroundColor3=deep
	else
		mark(.5,.5,.5,.5,45);mark(.5,.5,.18,.18,45).BackgroundColor3=deep
	end
end
local function revealSelection(object)
	local scroller=object:FindFirstAncestorWhichIsA("ScrollingFrame")
	if not scroller then return end
	local top=object.AbsolutePosition.Y-scroller.AbsolutePosition.Y
	local bottom=top+object.AbsoluteSize.Y
	local shift=if top<4 then top-4 elseif bottom>scroller.AbsoluteSize.Y-4 then bottom-scroller.AbsoluteSize.Y+4 else 0
	if shift~=0 then
		local maximum=math.max(0,scroller.AbsoluteCanvasSize.Y-scroller.AbsoluteSize.Y)
		scroller.CanvasPosition=Vector2.new(scroller.CanvasPosition.X,math.clamp(scroller.CanvasPosition.Y+shift,0,maximum))
	end
end
local function pressable(b)
	local pressScale=make("UIScale",b,{Scale=1})
	b.MouseButton1Down:Connect(function() TweenService:Create(pressScale,TweenInfo.new(.08),{Scale=.96}):Play() end)
	b.MouseButton1Up:Connect(function() TweenService:Create(pressScale,TweenInfo.new(.12),{Scale=1}):Play() end)
	b.MouseLeave:Connect(function() pressScale.Scale=1 end)
	b.SelectionGained:Connect(function() revealSelection(b) end)
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
	pressable(b)
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
	return badge
end
-- Original prop masters supply item art; no uploaded asset IDs are required.
local artCatalog
local catalogModule=ReplicatedStorage:WaitForChild("AetherArt",10)
if catalogModule then
	local ok,result=pcall(require,catalogModule)
	if ok and type(result)=="table" then artCatalog=result end
end
-- Static Depth definitions (skills, items, recipes, monsters). Optional: every
-- page degrades to a placeholder when the shared module is unavailable.
local Data
do
	local dataModule=ReplicatedStorage:WaitForChild("AetherData",10)
	if dataModule then
		local ok,result=pcall(require,dataModule)
		if ok and type(result)=="table" then Data=result end
	end
end

------------------------------------------------------------------------------
-- Defensive value helpers: every snapshot field may be missing or malformed.
------------------------------------------------------------------------------
local EMPTY=table.freeze({})
local function tbl(value) if type(value)=="table" then return value end return EMPTY end
local function num(value,default) if type(value)=="number" and value==value then return value end return default end
local function safeColor(hex,fallback)
	if type(hex)~="string" then return fallback or ivory end
	local ok,color=pcall(Color3.fromHex,hex)
	if ok and color then return color end
	return fallback or ivory
end
local function escape(text)
	return (tostring(text):gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;"))
end
local function paint(text,hex)
	return '<font color="#'..hex..'">'..text..'</font>'
end
local function lighten(hex,amount)
	if type(hex)~="string" or #hex~=6 then return "FFFFFF" end
	local out=""
	for i=1,5,2 do
		local value=tonumber(hex:sub(i,i+1),16) or 255
		out..=string.format("%02X",math.floor(value+(255-value)*amount+.5))
	end
	return out
end
local function fmt(value)
	value=num(value,0)
	local negative=value<0
	local rounded10=math.floor(math.abs(value)*10+.5)
	local whole,tenth=rounded10//10,rounded10%10
	local digits=tostring(whole)
	local grouped=digits:reverse():gsub("(%d%d%d)","%1,"):reverse()
	if grouped:sub(1,1)=="," then grouped=grouped:sub(2) end
	if tenth>0 then grouped..="."..tenth end
	return (negative and "-" or "")..grouped
end
local function short(value)
	value=num(value,0)
	if value>=1e6 then return string.format("%.1fM",value/1e6) elseif value>=1e4 then return string.format("%.1fk",value/1e3) end
	return fmt(value)
end
local function clock(seconds)
	seconds=math.max(0,math.floor(num(seconds,0)))
	if seconds>=3600 then return (seconds//3600).."h "..((seconds%3600)//60).."m" end
	if seconds>=60 then return (seconds//60).."m "..(seconds%60).."s" end
	return seconds.."s"
end
local function chance(value)
	value=num(value,0)*100
	if value>=10 then return math.floor(value+.5).."%" elseif value>=1 then return string.format("%.1f%%",value) end
	return string.format("%.2f%%",value)
end
local roman={"I","II","III","IV","V","VI","VII","VIII","IX","X"}
local function numeral(n) return roman[n] or tostring(n) end
local function initials(name)
	local out=""
	for word in tostring(name):gmatch("%a+") do
		out..=word:sub(1,1):upper()
		if #out>=2 then break end
	end
	return out~="" and out or "?"
end
local check, cross = paint("✓","9EE7D2"), paint("✗","E8806A")

local function itemDef(id) return Data and type(Data.Items)=="table" and Data.Items[id] or nil end
local function itemName(id) local def=itemDef(id) return def and def.name or tostring(id) end
local function rarityHex(rarity)
	local entry=Data and type(Data.Rarity)=="table" and Data.Rarity[rarity]
	return lighten(type(entry)=="table" and entry.color or "FFFFFF",.28)
end
local function rarityRank(rarity)
	local entry=Data and type(Data.Rarity)=="table" and Data.Rarity[rarity]
	return type(entry)=="table" and num(entry.rank,1) or 1
end
local function itemHex(id) local def=itemDef(id) return rarityHex(def and def.rarity or "Common") end
local extraStats={
	damage={name="Damage",symbol="⚔",color="FF5555"},damagePercent={name="Damage",symbol="⚔",color="FF5555",percent=true},
	lifesteal={name="Lifesteal",symbol="♥",color="FF5555",percent=true},fortune={name="Fortune",symbol="☘",color="FFAA00"},
	effectiveHealth={name="Effective Health",symbol="❤",color="FF5555"},magicalPower={name="Magical Power",symbol="✧",color="FFAA00"},
	combatBonus={name="Combat Bonus",symbol="⚔",color="C8553D",percent=true},
}
local extraOrder={"damage","damagePercent","lifesteal","fortune","effectiveHealth","magicalPower","combatBonus"}
local function statDef(key)
	local def=Data and type(Data.Stats)=="table" and Data.Stats[key]
	if type(def)=="table" then return def end
	return extraStats[key] or {name=tostring(key),symbol="•",color="FFFFFF"}
end
local function statKeys(stats)
	local keys,seen={},{}
	for _,key in ipairs(Data and Data.StatOrder or {}) do if stats[key]~=nil then table.insert(keys,key);seen[key]=true end end
	for _,key in ipairs(extraOrder) do if stats[key]~=nil and not seen[key] then table.insert(keys,key);seen[key]=true end end
	local rest={}
	for key in pairs(stats) do if type(key)=="string" and not seen[key] then table.insert(rest,key) end end
	table.sort(rest)
	for _,key in ipairs(rest) do table.insert(keys,key) end
	return keys
end
local function statValue(key,value)
	return fmt(value)..(statDef(key).percent and "%" or "")
end
-- Rich "+10 ❁ Strength, +5 ☠ Crit Damage" line in stat colours.
local function statText(stats,mult,separator)
	if type(stats)~="table" then return "" end
	mult=mult or 1
	local parts={}
	for _,key in ipairs(statKeys(stats)) do
		local value=num(stats[key],nil)
		if value and value*mult~=0 then
			local def=statDef(key)
			local amount=value*mult
			table.insert(parts,paint(escape((amount>0 and "+" or "")..statValue(key,amount).." "..(def.symbol or "").." "..(def.name or key)),lighten(def.color or "FFFFFF",.15)))
		end
	end
	return table.concat(parts,separator or ", ")
end
local slotNames={weapon="Weapon",helmet="Helmet",chest="Chestplate",legs="Greaves",boots="Boots",pickaxe="Pickaxe",hatchet="Hatchet",rod="Rod",hoe="Hoe"}
local gearSlots={"weapon","helmet","chest","legs","boots"}
local gearSlotSet={weapon=true,helmet=true,chest=true,legs=true,boots=true}
local function kindLabel(def)
	if not def then return "Item" end
	local kind=def.kind
	if kind=="weapon" then return "Weapon" elseif kind=="armor" then return slotNames[def.slot] or "Armor"
	elseif kind=="tool" then return def.toolKind or "Tool" elseif kind=="accessory" then return "Accessory" elseif kind=="pet" then return "Pet"
	elseif kind=="consumable" then return def.category=="food" and "Food" or def.category=="potion" and "Potion" or def.category=="buff" and "Feast" or "Consumable"
	elseif kind=="resource" then return (def.skill and (def.skill.." ") or "").."Resource" end
	return "Material"
end
local function levelForXp(xp)
	if not (Data and type(Data.XP_TABLE)=="table") then return 1 end
	xp=num(xp,0)
	local lo,hi=1,num(Data.MAX_LEVEL,#Data.XP_TABLE)
	while lo<hi do
		local mid=(lo+hi+1)//2
		if (Data.XP_TABLE[mid] or math.huge)<=xp then lo=mid else hi=mid-1 end
	end
	return lo
end
local function maxLevel() return Data and num(Data.MAX_LEVEL,99) or 99 end
local function xpAt(level) return Data and type(Data.XP_TABLE)=="table" and num(Data.XP_TABLE[level],nil) or nil end
local function fractionFor(xp)
	local level=levelForXp(xp)
	local floorXp,ceilXp=xpAt(level),xpAt(level+1)
	if not floorXp or not ceilXp or ceilXp<=floorXp then return level>=maxLevel() and 1 or 0 end
	return math.clamp((num(xp,0)-floorXp)/(ceilXp-floorXp),0,1)
end
local function skillOrder()
	return Data and type(Data.SkillOrder)=="table" and Data.SkillOrder or {"Combat","Mining","Woodcutting","Fishing","Farming","Smithing","Cooking","Alchemy","Enchanting","Taming","Dungeoneering","Carpentry"}
end
local function skillDef(skill) return Data and type(Data.Skills)=="table" and tbl(Data.Skills[skill]) or EMPTY end
local function skillHex(skill) local color=skillDef(skill).color return type(color)=="string" and color or "9EE7D2" end
-- Skill progress read from depth.skills, otherwise derived from lifetime XP.
local function skillsOf(snapshot)
	local out={}
	local depthSkills=type(snapshot.depth)=="table" and type(snapshot.depth.skills)=="table" and snapshot.depth.skills or nil
	local xpTable,levels=tbl(snapshot.xp),tbl(snapshot.levels)
	for _,skill in ipairs(skillOrder()) do
		local entry=depthSkills and depthSkills[skill]
		entry=type(entry)=="table" and entry or EMPTY
		local xp=num(entry.xp,nil) or num(xpTable[skill],0)
		local level=num(entry.level,nil) or (Data and levelForXp(xp)) or num(levels[skill],1)
		local maxed=entry.maxed==true or level>=maxLevel()
		local floorXp=num(entry.floor,nil) or xpAt(level) or 0
		local ceiling=num(entry.ceiling,nil) or xpAt(level+1) or floorXp
		local fraction=num(entry.fraction,nil) or (maxed and 1) or fractionFor(xp)
		out[skill]={xp=xp,level=level,maxed=maxed,floor=floorXp,ceiling=ceiling,fraction=math.clamp(fraction,0,1)}
	end
	return out
end

------------------------------------------------------------------------------
-- Item art: tinted prop thumbnails (Catalog.iconShape / tintIndex when the art
-- team ships them), pooled ViewportFrames and a cheap glyph fallback.
------------------------------------------------------------------------------
-- Each thumbnail is a per-triangle WedgePart model inside a ViewportFrame, so phone
-- (compact) layouts get a much smaller live/pooled budget.
-- (Kept in one table: this chunk is close to Luau's 200 top-level local limit.)
local TEMPLATE_LIMIT = 64
local THUMBS = { budget = 24, pool = 48, compactBudget = 10, compactPool = 20, compact = false }
function THUMBS.limits()
	if THUMBS.compact then return THUMBS.compactBudget, THUMBS.compactPool end
	return THUMBS.budget, THUMBS.pool
end
local artTemplates={}
local templateCount=0
local thumbnailCount=0
local viewPool,pooledViews,liveViews={},0,{}
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
local function tintIndex()
	return artCatalog and type(artCatalog.tintIndex)=="number" and artCatalog.tintIndex or nil
end
local function artTemplate(name,tint)
	local tintAt=type(tint)=="string" and tintIndex() or nil
	local key=tintAt and (name.."#"..tint) or name
	if artTemplates[key] then return artTemplates[key],key end
	local shapes=artCatalog and type(artCatalog.shapes)=="table" and artCatalog.shapes
	local data=shapes and shapes[name]
	if type(data)~="table" or type(data.faces)~="table" then return nil end
	if tintAt and templateCount>=TEMPLATE_LIMIT then return artTemplate(name) end
	local palette=tbl(artCatalog.palette)
	local tintColor=tintAt and safeColor(tint,mint)
	local model=Instance.new("Model")
	model.Name=name
	for _,face in ipairs(data.faces) do
		local color=if tintAt and face[4]==tintAt then tintColor else safeColor(palette[face[4]],slate)
		iconWedge(model,Vector3.new(table.unpack(data.vertices[face[1]])),Vector3.new(table.unpack(data.vertices[face[2]])),Vector3.new(table.unpack(data.vertices[face[3]])),color)
	end
	artTemplates[key]=model
	templateCount+=1
	return model,key
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
	elseif kind=="Hero" then
		local shield=stroke(.5,.5,.5,.62,0,mint);rounded(shield,5)
		stroke(.5,.5,.1,.48,0,gold);stroke(.5,.42,.36,.09,0,gold)
	elseif kind=="Hunt" then
		stroke(.5,.5,.1,.74,40,mint);stroke(.5,.5,.1,.74,-40,gold)
		local eye=stroke(.5,.5,.24,.24,45,ivory);rounded(eye,3)
	else
		stroke(.5,.5,.13,.68,35,mint);stroke(.5,.5,.13,.68,-55,gold)
		stroke(.5,.5,.24,.24,45,ivory)
	end
	return frame
end
-- ViewportFrames are expensive: a per-render budget plus a pool keyed by
-- template means rebuilding a page reuses the previous page's viewports.
local function thumbnail(parent,name,size,tint,noFallback)
	local template,key=artTemplate(name,tint)
	if not template or thumbnailCount>=(THUMBS.limits()) then
		if noFallback then return nil end
		return motif(parent,"Journal",size)
	end
	thumbnailCount+=1
	local bucket=viewPool[key]
	local view=bucket and table.remove(bucket)
	if view then
		pooledViews-=1
		view.Position=UDim2.new()
		view.AnchorPoint=Vector2.zero
		view.BackgroundTransparency=0
		view.Size=UDim2.fromOffset(size,size)
		view.Visible=true
		view.Parent=parent
	else
		view=make("ViewportFrame",parent,{Size=UDim2.fromOffset(size,size),BackgroundColor3=deep,BorderSizePixel=0,Ambient=rgb("B5D8DD"),LightColor=rgb("FFE1A6"),LightDirection=Vector3.new(-1,-1,-2)})
		rounded(view,9,slate)
		local model=template:Clone()
		model.Parent=view
		local cf,dimensions=model:GetBoundingBox()
		local radius=math.max(dimensions.X,dimensions.Y,dimensions.Z)
		local camera=make("Camera",view,{FieldOfView=34,CFrame=CFrame.lookAt(cf.Position+Vector3.new(.7,.38,-1).Unit*radius*2,cf.Position)})
		view.CurrentCamera=camera
	end
	liveViews[view]=key
	return view
end
local function releaseViews(container)
	for view,key in pairs(liveViews) do
		if view.Parent==nil or view:IsDescendantOf(container) then
			liveViews[view]=nil
			if view.Parent~=nil and pooledViews<select(2,THUMBS.limits()) then
				view.Parent=nil
				viewPool[key]=viewPool[key] or {}
				table.insert(viewPool[key],view)
				pooledViews+=1
			else
				view:Destroy()
			end
		end
	end
end
-- Drop pooled viewports beyond the current layout's pool budget.
function THUMBS.trim()
	local _,limit=THUMBS.limits()
	for key,bucket in pairs(viewPool) do
		while pooledViews>limit and #bucket>0 do
			table.remove(bucket):Destroy()
			pooledViews-=1
		end
		if #bucket==0 then viewPool[key]=nil end
	end
end
local iconMappings={
	{"ReinforcedPickaxe","Pickaxe"},{"Pickaxe","Pickaxe"},{"Skyplate","Skyplate"},{"AetherIngot","AetherIngot"},{"AlloyIngot","AlloyIngot"},
	{"Stormblade","Blade"},{"Blade","Blade"},{"Tonic","Tonic"},{"Timber","TimberBundle"},{"Woodcutting","WindpineCrown"},{"Mining","AetherCrystal"},
	{"Aetherite","AetherCrystal"},{"Ore","AetherCrystal"},{"Shard","AetherCrystal"},{"Stormglass","AetherCrystal"},{"Herb","Moonbloom"},{"Garden","Moonbloom"},
	{"Farming","Moonbloom"},{"Fish","Fish"},{"worker","Surveyor"},{"Worker","Surveyor"},{"Lantern","Lantern"},{"Vault","VaultChest"},{"Purse","VaultChest"},
	{"homestead","FloatingIslet"},{"Deck","FloatingIslet"},{"Smithing","AlloyIngot"},{"Combat","Blade"},{"Enchant","AetherCrystal"},{"Alchemy","Tonic"},
	{"Cooking","Fish"},{"Taming","Surveyor"},{"Dungeoneering","ObservatoryArch"},{"Carpentry","TimberBundle"},
}
local function titleArt(parent,title,size,page)
	if title:find("ExpeditionRation",1,true) then return motif(parent,"Ration",size) end
	for _,mapping in ipairs(iconMappings) do if title:find(mapping[1],1,true) then return thumbnail(parent,mapping[2],size) end end
	return motif(parent,page,size)
end
local skillShapes={Mining="AetherCrystal",Woodcutting="TimberBundle",Fishing="Fish",Farming="Moonbloom"}
local exactShapes={}
for _,mapping in ipairs(iconMappings) do exactShapes[mapping[1]]=mapping[2] end
local function shapeFor(id,def)
	local shapes=artCatalog and type(artCatalog.shapes)=="table" and artCatalog.shapes
	if not shapes then return nil end
	if type(artCatalog.iconShape)=="function" then
		local ok,shape=pcall(artCatalog.iconShape,def)
		if ok and type(shape)=="string" and shapes[shape] then return shape end
	end
	if exactShapes[id] then return exactShapes[id] end
	local kind=def.kind
	if kind=="weapon" then return "Blade" elseif kind=="armor" then return "Skyplate" elseif kind=="tool" then return "Pickaxe"
	elseif kind=="consumable" then return def.category=="food" and "Fish" or "Tonic"
	elseif kind=="resource" then return skillShapes[def.skill]
	elseif kind=="material" then return tostring(id):find("Ingot",1,true) and "AlloyIngot" or "AetherCrystal"
	elseif kind=="accessory" then return "AetherCrystal" end
	return nil
end
local function itemGlyph(parent,def,size,locked)
	local frame=panel(parent,UDim2.new(),UDim2.fromOffset(size,size),deep)
	rounded(frame,9)
	local gem=make("Frame",frame,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(.56,.56),Rotation=45,BackgroundColor3=locked and slate or safeColor(def and def.color,mint),BorderSizePixel=0})
	rounded(gem,math.max(2,size//10))
	make("UIGradient",gem,{Color=ColorSequence.new(Color3.new(1,1,1),rgb("7A9AA3")),Rotation=90})
	local caption=label(frame,locked and "?" or initials(def and def.name or "?"),0,0,full,size,bold,locked and math.floor(size*.45) or math.max(9,math.floor(size*.28)),locked and muted or ivory)
	caption.Size=UDim2.fromScale(1,1)
	caption.TextXAlignment=Enum.TextXAlignment.Center
	caption.TextYAlignment=Enum.TextYAlignment.Center
	caption.TextStrokeTransparency=.35
	caption.TextStrokeColor3=deep
	return frame
end
-- Item icon with a rarity-coloured rim. locked shows a "?" (undiscovered).
local function itemIcon(parent,id,size,locked)
	local def=itemDef(id)
	local holder=make("Frame",parent,{Name="ItemIcon",BackgroundTransparency=1,Size=UDim2.fromOffset(size,size),BorderSizePixel=0})
	make("UICorner",holder,{CornerRadius=UDim.new(0,9)})
	local art
	local tinted=tintIndex()~=nil and def~=nil and type(def.color)=="string"
	if not locked and def then
		local shape=shapeFor(id,def)
		if shape then art=thumbnail(holder,shape,size,tinted and def.color or nil,true) end
	end
	if not art then
		itemGlyph(holder,def or {name=tostring(id)},size,locked)
	elseif not tinted and def and type(def.color)=="string" then
		local dot=make("Frame",holder,{Name="Swatch",Position=UDim2.new(0,4,1,-10),Size=UDim2.fromOffset(6,6),BackgroundColor3=safeColor(def.color,mint),BorderSizePixel=0})
		make("UICorner",dot,{CornerRadius=UDim.new(1,0)})
	end
	make("UIStroke",holder,{Name="Rarity",Color=locked and slate or rgb(rarityHex(def and def.rarity or "Common")),Thickness=locked and 1 or 1.5,Transparency=locked and .3 or .05})
	return holder
end

------------------------------------------------------------------------------
-- HUD: guild badge, SkyBlock-style action bar, XP popups, level-up banner.
------------------------------------------------------------------------------
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
local actionBar=make("Frame",gui,{Name="ActionBar",AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-8),Size=UDim2.new(.94,0,0,30),BackgroundColor3=deep,BackgroundTransparency=.22,BorderSizePixel=0})
make("UISizeConstraint",actionBar,{MaxSize=Vector2.new(520,30)})
rounded(actionBar,9,slate)
local healthText=label(actionBar,"❤ —",12,0,UDim.new(.3,-12),30,bold,15,rgb("FF6B6B"))
local defenseText=label(actionBar,"❈ —",0,0,UDim.new(.3,-12),30,bold,15,rgb("6BFF8E"))
defenseText.Position=UDim2.new(.7,0,0,0)
defenseText.TextXAlignment=Enum.TextXAlignment.Right
-- XP popup owns the middle 40% between the health (0-30%) and defense (70-100%)
-- readouts and shrinks its text instead of spilling over them.
local xpText=label(actionBar,"",0,0,UDim.new(.4,0),30,bold,13,gold)
xpText.Name="XpPopup"
xpText.Position=UDim2.new(.3,0,0,0)
xpText.TextXAlignment=Enum.TextXAlignment.Center
xpText.RichText=true
xpText.TextWrapped=false
xpText.TextScaled=true
make("UITextSizeConstraint",xpText,{MinTextSize=8,MaxTextSize=13})
xpText.TextTransparency=1
-- Level-up banner sits below the top HUD row: the combat target panel and its
-- banner own y 10-138 (combat.client.lua), the atlas HUD the top-left corner.
local banner=panel(gui,UDim2.new(.5,0,0,140),UDim2.new(.9,0,0,74),deep)
banner.Name="LevelBanner"
banner.AnchorPoint=Vector2.new(.5,0)
banner.Visible=false
banner.ZIndex=5
make("UISizeConstraint",banner,{Name="BannerLimit",MaxSize=Vector2.new(420,74)})
rounded(banner,12,gold)
local bannerScale=make("UIScale",banner,{Scale=1})
local bannerKicker=label(banner,"L E V E L   U P",0,6,full,16,bold,11,gold)
bannerKicker.TextXAlignment=Enum.TextXAlignment.Center
local bannerTitle=label(banner,"",0,21,full,30,book,24,ivory)
bannerTitle.TextXAlignment=Enum.TextXAlignment.Center
local bannerReward=label(banner,"",8,50,UDim.new(1,-16),20,bold,12,muted)
bannerReward.TextXAlignment=Enum.TextXAlignment.Center
bannerReward.RichText=true
bannerReward.TextScaled=true
make("UITextSizeConstraint",bannerReward,{MinTextSize=10,MaxTextSize=12})

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
local compassBadge=compass(head, 13, 10, 43)
local guildLabel=label(head, "CARTOGRAPHERS' GUILD", 68, 6, UDim.new(1, -138), 19, bold, 10, mint)
local titleLabel=label(head, "Voyager’s Atlas", 67, 24, UDim.new(1, -138), 33, book, 27, ivory)
local mastheadCaption=label(head,"CHART YOUR COURSE  /  BUILD YOUR LEGACY",16,61,UDim.new(1,-32),17,bold,10,gold)
local edge=panel(head,UDim2.new(0,14,1,-3),UDim2.new(1,-28,0,1),gold)
edge.BackgroundTransparency=.5
local function closeAtlas()
	atlas.Visible = false
	shade.Visible = false
	hud.Visible = true
	actionBar.Visible = true
	-- Leave UI selection entirely so gamepad input drives the character again.
	GuiService.SelectedObject = nil
end
local closeButton=button(head, "Close", UDim2.new(1, -64, 0, 10), UDim2.fromOffset(54, 43), closeAtlas)
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
notice.Position = UDim2.new(0.5, 0, 1, -46)
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
make("UISizeConstraint", notice, { Name = "NoticeLimit", MaxSize = Vector2.new(560, 180) })
local noticeIndex = 0
local function notify(message)
	if type(message)~="string" or message == "" then
		return
	end
	-- Phones (compact layout): one short strip that stays clear of touch controls.
	local compactToast = THUMBS.compact
	notice:FindFirstChild("NoticeLimit").MaxSize = compactToast and Vector2.new(340, 60) or Vector2.new(560, 180)
	notice.TextSize = compactToast and 12 or 13
	notice.TextTruncate = compactToast and Enum.TextTruncate.AtEnd or Enum.TextTruncate.None
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
local railMode = false
local render, send, sendCoop
local coopState, coopError
local coopPending = false
local coopConfirm = nil
local tabButtons = {}
local order = 0
local sectionOf -- selected section per primary tab (filled in by the navigation block)
local enchantTarget -- item chosen on the Enchant section
local function depth() local d=state.depth if type(d)=="table" then return d end return nil end
local function dget(key) local d=depth() if d and type(d[key])=="table" then return d[key] end return nil end
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
-- Simple title/detail/action rows share the card style (forward-declared card).
local card
local function row(title, detail, tag, callback)
	card({icon=function(parent,size) return titleArt(parent,title,size,current) end,title=escape(title),detail=escape(detail),
		actions=tag and {{caption=tag,primary=tag~="Locked" and tag~="Cancel",name=tag:gsub("[^%w]","").."Button",fn=callback}} or nil})
end
local function count(map, key)
	local source=state[map]
	return type(source)=="table" and num(source[key],0) or 0
end
local function para(parent,value,order,color,size)
	return make("TextLabel",parent,{Name="Copy",Text=value,RichText=true,BackgroundTransparency=1,Font=regular,TextSize=size or (compactAtlas and 12 or 13),TextColor3=color or muted,
		TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,TextWrapped=true,Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,LayoutOrder=order or 0})
end
local function progress(parent,fraction,color,caption,height)
	height=height or (compactAtlas and 14 or 16)
	local bar=make("Frame",parent,{Name="Progress",BackgroundColor3=track,BorderSizePixel=0,Size=UDim2.new(1,0,0,height)})
	make("UICorner",bar,{CornerRadius=UDim.new(0,height//2)})
	make("UIStroke",bar,{Color=slate,Transparency=.2,Thickness=1})
	local fill=make("Frame",bar,{Name="Fill",BackgroundColor3=color or mint,BorderSizePixel=0,Size=UDim2.new(math.clamp(num(fraction,0),0,1),0,1,0)})
	make("UICorner",fill,{CornerRadius=UDim.new(0,height//2)})
	make("UIGradient",fill,{Color=ColorSequence.new(Color3.new(1,1,1),rgb("9FB8BC")),Rotation=90})
	if caption then
		local text=label(bar,caption,0,0,full,height,bold,math.max(9,height-4),ivory)
		text.TextXAlignment=Enum.TextXAlignment.Center
		text.TextStrokeTransparency=.35
		text.TextStrokeColor3=deep
	end
	return bar
end
local function pips(parent,total,filled,color,labels)
	local strip=make("Frame",parent,{Name="Pips",BackgroundTransparency=1,Size=UDim2.new(1,0,0,compactAtlas and 16 or 18)})
	for i=1,total do
		local reached=i<=filled
		local pip=make("Frame",strip,{Position=UDim2.new((i-1)/total,1,0,0),Size=UDim2.new(1/total,-3,1,0),BackgroundColor3=reached and (color or gold) or track,BorderSizePixel=0})
		make("UICorner",pip,{CornerRadius=UDim.new(0,4)})
		if not reached then make("UIStroke",pip,{Color=slate,Transparency=.3,Thickness=1}) end
		if labels and labels[i] then
			local text=label(pip,labels[i],0,0,full,compactAtlas and 16 or 18,bold,10,reached and deep or muted)
			text.Size=UDim2.fromScale(1,1)
			text.TextXAlignment=Enum.TextXAlignment.Center
		end
	end
	return strip
end
local function container(height)
	return listItem(make("Frame",scroll,{Name="Group",BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.new(1,-7,0,height or 0),AutomaticSize=height and Enum.AutomaticSize.None or Enum.AutomaticSize.Y}))
end
local function gridHolder(cell,padding)
	local holder=container()
	make("UIGridLayout",holder,{CellSize=cell,CellPadding=UDim2.fromOffset(padding or 6,padding or 6),SortOrder=Enum.SortOrder.LayoutOrder})
	return holder
end
local function tile(parent,name,layoutOrder,action)
	local b=make("TextButton",parent,{Name=name,Text="",AutoButtonColor=true,BackgroundColor3=deep,BorderSizePixel=0,Selectable=true,LayoutOrder=layoutOrder or 0,ClipsDescendants=true})
	make("UICorner",b,{CornerRadius=UDim.new(0,10)})
	pressable(b)
	b.Activated:Connect(action)
	return b
end
local function contentWidth()
	local width=scroll.AbsoluteSize.X
	if type(width)~="number" or width<=0 then width=compactAtlas and 420 or 700 end
	return width-7
end
-- Shared card: icon band (item art, motif or custom), rich title/subtitle,
-- badge, copy lines, progress bar, pips and right-aligned actions.
function card(o)
	local box=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,0),o.fill or deep))
	box.AutomaticSize=Enum.AutomaticSize.Y
	if o.name then box.Name=o.name end
	rounded(box,10,o.edge or slate)
	if o.accent then
		local strip=make("Frame",box,{Name="Accent",Position=UDim2.fromOffset(0,8),Size=UDim2.new(0,4,1,-16),BackgroundColor3=o.accent,BorderSizePixel=0})
		make("UICorner",strip,{CornerRadius=UDim.new(0,2)})
	end
	local body=make("Frame",box,{Name="Body",BackgroundTransparency=1,Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y})
	local pad=compactAtlas and 9 or 11
	make("UIPadding",body,{PaddingTop=UDim.new(0,pad),PaddingBottom=UDim.new(0,pad),PaddingLeft=UDim.new(0,pad+(o.accent and 4 or 0)),PaddingRight=UDim.new(0,pad)})
	make("UIListLayout",body,{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6)})
	local index=0
	local function nextOrder() index+=1 return index end
	local iconSize=o.iconSize or (compactAtlas and 36 or 46)
	local hasIcon=o.item~=nil or o.icon~=nil or o.motif~=nil or o.locked
	local titleSize=compactAtlas and 14 or 16
	local bandHeight=hasIcon and iconSize or (o.subtitle and 38 or 20)
	local band=make("Frame",body,{Name="Band",BackgroundTransparency=1,Size=UDim2.new(1,0,0,bandHeight),LayoutOrder=nextOrder()})
	local textX=0
	if hasIcon then
		if o.item~=nil or o.locked then itemIcon(band,o.item,iconSize,o.locked)
		elseif o.icon then o.icon(band,iconSize)
		else motif(band,o.motif,iconSize) end
		textX=iconSize+10
	end
	-- Badge column grows with its copy (rich tags stripped) instead of truncating.
	local badgeWidth=0
	if o.badge then
		local plain=tostring(o.badge):gsub("<[^>]+>","")
		badgeWidth=math.clamp((utf8.len(plain) or #plain)*(compactAtlas and 9 or 10)+10,compactAtlas and 64 or 84,compactAtlas and 150 or 190)
	end
	local blockHeight=20+(o.subtitle and 18 or 0)
	local top=math.max(0,(bandHeight-blockHeight)//2)
	local title=label(band,o.title or "",textX,top,UDim.new(1,-textX-badgeWidth-4),20,bold,titleSize,o.titleColor or ivory)
	title.RichText=true
	if o.subtitle then
		local sub=label(band,o.subtitle,textX,top+20,UDim.new(1,-textX-badgeWidth-4),17,regular,12,o.subtitleColor or muted)
		sub.RichText=true
	end
	if o.badge then
		local badge=label(band,o.badge,0,0,UDim.new(0,badgeWidth),20,bold,compactAtlas and 12 or 13,o.badgeColor or gold)
		badge.Position=UDim2.new(1,-badgeWidth,0,top)
		badge.TextXAlignment=Enum.TextXAlignment.Right
		badge.RichText=true
	end
	if type(o.detail)=="string" and o.detail~="" then para(body,o.detail,nextOrder(),o.detailColor) end
	local lines=o.lines or EMPTY
	for i=1,16 do
		local line=lines[i]
		if type(line)=="string" and line~="" then para(body,line,nextOrder(),o.linesColor or muted) end
	end
	if o.pips then pips(body,o.pips.total,o.pips.filled,o.pips.color,o.pips.labels).LayoutOrder=nextOrder() end
	if o.bar then progress(body,o.bar.fraction,o.bar.color,o.bar.caption).LayoutOrder=nextOrder() end
	if o.after then o.after(body,nextOrder) end
	if o.actions and #o.actions>0 then
		local height=compactAtlas and 38 or 42
		local width=compactAtlas and 100 or 116
		local strip=make("Frame",body,{Name="Actions",BackgroundTransparency=1,Size=UDim2.new(1,0,0,height),LayoutOrder=nextOrder()})
		local total=#o.actions*width+(#o.actions-1)*6
		for i,action in ipairs(o.actions) do
			local x=-total+(i-1)*(width+6)
			local b=button(strip,action.caption,UDim2.new(1,x,0,0),UDim2.fromOffset(width,height),function()
				if action.disabled then notify(action.reason or "Not available yet.") return end
				action.fn()
			end)
			b.Name=action.name or ((o.name or "Card")..(action.caption:gsub("[^%w]","")))
			b.TextScaled=true
			make("UITextSizeConstraint",b,{MinTextSize=11,MaxTextSize=14})
			if action.disabled then b.BackgroundColor3=ink;b.TextColor3=muted end
			if action.primary then b.BackgroundColor3=rgb("2F6D63") end
		end
	end
	return box
end
-- Segmented control used for primary-page sections and in-page filters.
local function sectionBar(options,selected,onPick,opts)
	opts=opts or {}
	local n=#options
	if n==0 then return end
	local maxPer=opts.maxPer or ((compactAtlas and not railMode) and 3 or 6)
	local rows=math.ceil(n/maxPer)
	local per=math.ceil(n/rows)
	local height=opts.small and (compactAtlas and 32 or 36) or (compactAtlas and 38 or 44)
	local holder=container(rows*height+(rows-1)*4)
	for i,name in ipairs(options) do
		local r,c=(i-1)//per,(i-1)%per
		local b=button(holder,name,UDim2.new(c/per,0,0,r*(height+4)),UDim2.new(1/per,-4,0,height),function() onPick(name) end)
		b.Name=(opts.prefix or "Section")..(tostring(name):gsub("[^%w]",""))
		b.TextScaled=true
		make("UITextSizeConstraint",b,{MinTextSize=11,MaxTextSize=compactAtlas and 13 or 14})
		if opts.small or per>3 then
			local engraving=b:FindFirstChild("ControlEngraving")
			if engraving then engraving:Destroy() end
		end
		local on=name==selected
		b.BackgroundColor3=on and mint or slate
		b.TextColor3=on and deep or ivory
	end
end
local function syncing(what)
	card({motif="Journal",title="Syncing…",subtitle="Waiting for the isles' ledger",titleColor=gold,
		detail="Your "..what.." will appear as soon as the server shares your Depth record. Keep exploring; nothing is lost."})
end
local function dataMissing()
	card({motif="Journal",title="Field guide loading…",titleColor=gold,detail="Skill and item records have not arrived yet. Reopen the atlas in a moment."})
end
local function meetsRequires(requires,levels)
	local parts,ok={},true
	for _,skill in ipairs(skillOrder()) do
		local need=type(requires)=="table" and num(requires[skill],nil)
		if need then
			local have=levels[skill] and levels[skill].level or 1
			local met=have>=need
			if not met then ok=false end
			table.insert(parts,(met and check or cross).." "..skill.." "..need)
		end
	end
	return ok,table.concat(parts,"  ")
end
local function equippedSlotOf(id)
	for slot,item in pairs(tbl(dget("equipment"))) do if item==id then return slot end end
	return nil
end
local function collectionThreshold(id,tier)
	local tiers=Data and type(Data.CollectionTiers)=="table" and Data.CollectionTiers
	if not tiers or not tiers[tier] then return nil end
	local scale=Data.CollectionScale and num(Data.CollectionScale[id],1) or 1
	return math.max(1,math.floor(tiers[tier]*scale))
end
local function collectionTierCount() return Data and type(Data.CollectionTiers)=="table" and #Data.CollectionTiers or 9 end
local function collectionInfo(id)
	local entry=tbl(tbl(dget("collections"))[id])
	local amount=num(entry.count,nil) or count("collection",id)
	local tier=num(entry.tier,nil)
	if not tier then
		tier=0
		for t=1,collectionTierCount() do
			local need=collectionThreshold(id,t)
			if need and amount>=need then tier=t else break end
		end
	end
	local nextAt=num(entry.nextAt,nil) or collectionThreshold(id,tier+1)
	return amount,tier,nextAt
end

-- Page modules live in do-blocks (Luau caps a chunk at 200 locals) and export
-- their draw functions through Pages; state shared across pages stays here.
local Pages={}
local confirmIron=false
local sellConfirm
local abandonConfirm=false
local purchaseReview
local marketItem="Ore"
local marketQuotes,marketChanges={},{}
local function enchantKind(def)
	if not def then return nil end
	if def.kind=="weapon" or def.kind=="armor" or def.kind=="tool" then return def.kind end
	return nil
end
------------------------------------------------------------------------------
-- Journal
------------------------------------------------------------------------------
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
do
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
local function drawBearing()
	local goal, detail = nextGoal()
	heading("01    /    NEXT BEARING")
	row(goal, detail)
	routeChart()
	if type(state.quest)=="table" then
		row(tostring(state.quest.title or "Guild contract"), tostring(state.quest.detail or ""), state.quest.ready and "Claim" or nil, function()
			send("quest")
		end)
	end
	heading("02    /    EXPEDITION RULES")
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
local function drawRegions()
	heading("REGIONS    /    EXPEDITION CHARTERS")
	local regions=dget("regions")
	if regions and #regions>0 then
		for _,region in ipairs(regions) do
			if type(region)=="table" then
				local def=Data and type(Data.RegionById)=="table" and tbl(Data.RegionById[region.id]) or EMPTY
				local names={}
				for _,id in ipairs(tbl(def.monsters)) do
					local monster=Data and type(Data.Monsters)=="table" and Data.Monsters[id]
					if type(monster)=="table" then table.insert(names,monster.name) end
				end
				local unlocked=region.unlocked==true
				card({name="Region"..tostring(region.id),motif="Journal",title=escape(region.name or def.name or region.id or "Region"),titleColor=unlocked and ivory or muted,
					subtitle=unlocked and paint("Charter open","9EE7D2") or paint("Locked  ·  "..escape(region.requirement or "Requirements unknown"),"E8806A"),
					badge=unlocked and "OPEN" or "LOCKED",badgeColor=unlocked and mint or ember,
					detail=type(def.description)=="string" and escape(def.description) or nil,
					lines={#names>0 and ("Creatures: "..escape(table.concat(names,", "))) or nil}})
			end
		end
		return
	end
	if type(state.regions)=="table" and #state.regions>0 then
		for _,region in ipairs(state.regions) do
			if type(region)=="table" then
				row(tostring(region.name or "Region"),region.visited and "Survey complete. Return through the Brassfall Quarry transit beacon." or (region.unlocked and "Charter unlocked. Travel from Brassfall Quarry and survey the region." or tostring(region.requirement or "")))
			end
		end
		return
	end
	if not depth() then syncing("region charters") else row("No charters yet","Complete guild contracts to open new regions.") end
end

Pages.drawBearing,Pages.drawRegions=drawBearing,drawRegions
end

------------------------------------------------------------------------------
-- Journal: quest log, achievement diaries and the Builder's Terrace
-- (snapshot.journal; static definitions from Data.Quests/Diaries/Furniture).
------------------------------------------------------------------------------
do
local QJ={line="Main",region="Meadow",hotspot="Bench",lampFor=nil,removeFor=nil}
local function journal() local j=state.journal if type(j)=="table" then return j end return nil end
local function journalData()
	return Data and type(Data.Quests)=="table" and type(Data.Diaries)=="table" and type(Data.Furniture)=="table"
		and type(Data.describeCheck)=="function"
end
local function checkLine(o,pair)
	local ok,text=pcall(Data.describeCheck,o)
	text=ok and type(text)=="string" and text or "Task"
	local have,need=num(tbl(pair)[1],0),num(tbl(pair)[2],num(type(o)=="table" and (o.count or o.level or o.tier) or 1,1))
	local met=have>=need
	local amount=if need>1 then "  "..paint(fmt(have).." / "..fmt(need),met and "9EE7D2" or "B9C7CC") else ""
	return (met and check or cross).." "..escape(text)..amount,met
end
local function statText(stats)
	local parts={}
	for stat,v in pairs(tbl(stats)) do
		local def=Data.Stats and Data.Stats[stat]
		table.insert(parts,"+"..fmt(v).." "..(def and def.name or stat))
	end
	table.sort(parts)
	return table.concat(parts,", ")
end
local function rewardText(r)
	r=tbl(r)
	local parts={}
	if num(r.points,0)>0 then table.insert(parts,r.points.." Quest Point"..(r.points==1 and "" or "s")) end
	if num(r.coins,0)>0 then table.insert(parts,fmt(r.coins).." coins") end
	for skill,amount in pairs(tbl(r.xp)) do table.insert(parts,fmt(amount).." "..skill.." XP") end
	if type(r.lamp)=="table" then
		local skills=type(r.lamp.skills)=="table" and table.concat(r.lamp.skills,"/")
			or (type(r.lamp.exclude)=="table" and #r.lamp.exclude>0 and ("any skill but "..table.concat(r.lamp.exclude,"/"))) or "any skill"
		table.insert(parts,"XP lamp: "..fmt(r.lamp.xp).." ("..skills..")")
	end
	for id,n in pairs(tbl(r.items)) do
		local def=Data.Items[id]
		table.insert(parts,n.." "..(def and def.name or id))
	end
	if type(r.perk)=="table" then table.insert(parts,"Perk "..statText(r.perk)) end
	local unlock=tbl(r.unlock)
	if num(unlock.accessorySlots,0)>0 then table.insert(parts,"+"..unlock.accessorySlots.." accessory slot") end
	if num(unlock.workerHaste,0)>0 then table.insert(parts,"Workers "..math.floor(unlock.workerHaste*100+.5).."% faster") end
	if type(unlock.shortcut)=="string" then table.insert(parts,"Portal attunement: "..unlock.shortcut) end
	return escape(table.concat(parts,"  ·  "))
end
local function questStatus(entry)
	if entry.done==true then return "DONE",mint end
	if entry.ready==true then return "READY",gold end
	if entry.available==true then return "ACTIVE",ivory end
	return "LOCKED",ember
end
local function drawQuests()
	local j=journal()
	heading("QUEST LOG    /    "..fmt(j and j.questPoints or 0).." QUEST POINTS")
	if not journalData() then dataMissing() return end
	if not j then syncing("quest log") return end
	sectionBar({"Main","Side"},QJ.line,function(name) QJ.line=name QJ.lampFor=nil render() end,{small=true,prefix="QuestLine"})
	local entries={}
	for _,entry in ipairs(tbl(j.quests)) do if type(entry)=="table" and type(entry.id)=="string" then entries[entry.id]=entry end end
	local shown=0
	for _,q in ipairs(Data.Quests) do
		if (q.line=="main")==(QJ.line=="Main") then
			local entry=entries[q.id] or EMPTY
			local badge,color=questStatus(entry)
			local lines={}
			-- Grouped copy: a gold caption per group, indented checklist beneath it.
			local function group(caption) table.insert(lines,"<b>"..paint(caption,"F9CC77").."</b>") end
			if entry.done~=true then
				if #q.requires>0 then group("REQUIRES") end
				for i,o in ipairs(q.requires) do table.insert(lines,"   "..(checkLine(o,tbl(entry.requires)[i]))) end
				if #q.objectives>0 then group("TASKS") end
				for i,o in ipairs(q.objectives) do table.insert(lines,"   "..(checkLine(o,tbl(entry.objectives)[i]))) end
			end
			group("REWARDS")
			table.insert(lines,"   "..rewardText(q.rewards))
			local actions={}
			local lamp=type(q.rewards.lamp)=="table" and q.rewards.lamp
			local picking=QJ.lampFor==q.id and entry.ready==true and lamp
			if entry.ready==true then
				if picking then
					table.insert(actions,{caption="Cancel",fn=function() QJ.lampFor=nil render() end})
				else
					table.insert(actions,{caption="Claim",primary=true,fn=function()
						if lamp then QJ.lampFor=q.id render() else send("quest",q.id) end
					end})
				end
			end
			local region=Data.RegionById and Data.RegionById[q.region]
			card({name="Quest"..q.id,motif="Journal",title=escape(q.title),titleColor=entry.done==true and muted or ivory,
				subtitle=escape((region and region.name or q.region).."  ·  "..(q.line=="main" and "Main quest" or "Side quest")),
				badge=badge,badgeColor=color,detail=entry.done~=true and escape(q.story or "") or nil,lines=lines,actions=actions,
				after=picking and function(body,nextOrder)
					para(body,"Choose a skill for your "..fmt(lamp.xp).." XP lamp:",nextOrder(),gold)
					-- lamp.exclude names skills the server refuses for this lamp (e.g. Dungeoneering, Carpentry).
					local skills={}
					for _,skill in ipairs(type(lamp.skills)=="table" and lamp.skills or Data.SkillOrder) do
						if not (type(lamp.exclude)=="table" and table.find(lamp.exclude,skill)) then table.insert(skills,skill) end
					end
					local per=compactAtlas and 3 or 4
					local height=compactAtlas and 34 or 38
					local rows=math.ceil(#skills/per)
					local grid=make("Frame",body,{Name="LampPicker",BackgroundTransparency=1,Size=UDim2.new(1,0,0,rows*(height+4)),LayoutOrder=nextOrder()})
					for i,skill in ipairs(skills) do
						local r,c=(i-1)//per,(i-1)%per
						local b=button(grid,skill,UDim2.new(c/per,0,0,r*(height+4)),UDim2.new(1/per,-4,0,height),function()
							QJ.lampFor=nil
							send("quest",q.id..":"..skill)
						end)
						b.Name="Lamp"..skill
						b.TextScaled=true
						make("UITextSizeConstraint",b,{MinTextSize=11,MaxTextSize=13})
					end
				end or nil})
			shown+=1
		end
	end
	if shown==0 then row("No quests","The guild has no work of this kind yet.") end
end
local function drawDiaries()
	heading("ACHIEVEMENT DIARIES")
	if not journalData() then dataMissing() return end
	local j=journal()
	if not j then syncing("diaries") return end
	local regions={}
	for _,d in ipairs(Data.Diaries) do table.insert(regions,d.region) end
	if not Data.DiaryByRegion[QJ.region] then QJ.region=regions[1] end
	sectionBar(regions,QJ.region,function(name) QJ.region=name render() end,{small=true,prefix="Diary",maxPer=compactAtlas and 4 or 7})
	local entry=EMPTY
	local total=0
	for _,e in ipairs(tbl(j.diaries)) do
		if type(e)=="table" then
			total+=math.clamp(num(e.claimed,0),0,4)
			if e.region==QJ.region then entry=e end
		end
	end
	local diary=Data.DiaryByRegion[QJ.region]
	local claimed=num(entry.claimed,0)
	card({name="DiarySummary",motif="Hunt",title=escape(diary.name),titleColor=gold,
		subtitle=claimed.." / "..#Data.DiaryTiers.." tiers claimed  ·  "..total.." / "..(#Data.Diaries*#Data.DiaryTiers).." across the isles",
		pips={total=#Data.DiaryTiers,filled=claimed,color=gold,labels={"Easy","Medium","Hard","Elite"}}})
	local tiers={}
	for _,t in ipairs(tbl(entry.tiers)) do if type(t)=="table" and type(t.tier)=="string" then tiers[t.tier]=t end end
	for index,tierName in ipairs(Data.DiaryTiers) do
		local def=diary.tiers[tierName]
		local t=tiers[tierName] or EMPTY
		local lines,done={},0
		for i,o in ipairs(def.tasks) do
			local text,met=checkLine(o,tbl(t.tasks)[i])
			if met then done+=1 end
			table.insert(lines,text)
		end
		table.insert(lines,"Perk  "..escape(statText(def.perk)).."  ·  "..fmt(Data.DiaryCoins[tierName]).." coins")
		local isClaimed=t.claimed==true or index<=claimed
		local badge,color="IN PROGRESS",ivory
		if isClaimed then badge,color="CLAIMED",mint
		elseif t.claimable==true then badge,color="READY",gold
		elseif index>claimed+1 then badge,color="LOCKED",ember end
		card({name="Diary"..QJ.region..tierName,motif="Hunt",title=tierName,titleColor=isClaimed and mint or ivory,badge=badge,badgeColor=color,
			lines=lines,bar={fraction=done/#def.tasks,color=isClaimed and mint or gold,caption=done.." / "..#def.tasks.." tasks"},
			actions=t.claimable==true and {{caption="Claim",primary=true,fn=function() send("diary",QJ.region..":"..tierName) end}} or nil})
	end
end
local function costLine(costs)
	local parts,ok={},true
	local ids={}
	for id in pairs(costs) do table.insert(ids,id) end
	table.sort(ids)
	for _,id in ipairs(ids) do
		local need=costs[id]
		local have=count("items",id)
		local met=have>=need
		if not met then ok=false end
		local def=Data.Items[id]
		table.insert(parts,(met and check or cross).." "..fmt(need).." "..escape(def and def.name or id).." "..paint("("..fmt(have)..")","B9C7CC"))
	end
	return table.concat(parts,"   "),ok
end
local function drawConstruction()
	heading("BUILDER'S TERRACE    /    CARPENTRY")
	if not journalData() then dataMissing() return end
	local j=journal()
	if not j then syncing("terrace plans") return end
	local con=tbl(j.construction)
	local furniture=tbl(con.furniture)
	local carpentry=num(con.carpentry,1)
	local portal=type(con.portal)=="string" and Data.RegionById[con.portal]
	card({name="TerraceSummary",motif="Workshop",title="Carpentry "..carpentry,titleColor=gold,
		subtitle="Build on the terrace west of your home landing",
		lines={"Bonus accessory slots  +"..fmt(num(con.accessorySlots,0)).."   ·   Worker speed  +"..math.floor(num(con.workerHaste,0)*100+.5).."%",
			"Home portal  "..(portal and escape(portal.name) or (furniture.Portal and "not attuned" or "no portal built")),
			"Removing furniture returns "..math.floor(num(Data.FurnitureRefund,.5)*100).."% of its materials."}})
	local names={}
	for _,h in ipairs(Data.Hotspots) do table.insert(names,h.id) end
	if not Data.HotspotById[QJ.hotspot] then QJ.hotspot=names[1] end
	sectionBar(names,QJ.hotspot,function(name) QJ.hotspot=name QJ.removeFor=nil render() end,{small=true,prefix="Hotspot",maxPer=(compactAtlas and not railMode) and 4 or 7})
	local h=Data.HotspotById[QJ.hotspot]
	local currentId=type(furniture[h.id])=="string" and Data.Furniture[furniture[h.id]] and furniture[h.id] or nil
	local current=currentId and Data.Furniture[currentId]
	local actions={}
	if current then
		if QJ.removeFor==h.id then
			table.insert(actions,{caption="Keep",fn=function() QJ.removeFor=nil render() end})
			table.insert(actions,{caption="Dismantle",fn=function() QJ.removeFor=nil send("remove",h.id) end})
		else
			table.insert(actions,{caption="Remove",fn=function() QJ.removeFor=h.id render() end})
		end
	end
	card({name="Hotspot"..h.id.."Current",motif="Workshop",title=escape(h.name),titleColor=ivory,
		subtitle=current and paint("Built: "..escape(current.name),"9EE7D2") or paint("Empty hotspot","B9C7CC"),
		badge=current and "BUILT" or "EMPTY",badgeColor=current and mint or muted,
		detail=current and escape(current.text) or "Choose a plan below. One piece per hotspot.",
		lines={QJ.removeFor==h.id and paint("Dismantle for a partial refund?","E8806A") or nil},actions=actions,
		after=current and current.effect.portal and function(body,nextOrder)
			local regions=tbl(con.portalRegions)
			para(body,"Attune the portal:",nextOrder(),gold)
			local per=compactAtlas and 3 or 5
			local height=compactAtlas and 34 or 38
			local grid=make("Frame",body,{Name="PortalPicker",BackgroundTransparency=1,Size=UDim2.new(1,0,0,math.max(1,math.ceil(#regions/per))*(height+4)),LayoutOrder=nextOrder()})
			for i,region in ipairs(regions) do
				if type(region)=="string" and Data.RegionById[region] then
					local r,c=(i-1)//per,(i-1)%per
					local b=button(grid,Data.RegionById[region].name,UDim2.new(c/per,0,0,r*(height+4)),UDim2.new(1/per,-4,0,height),function() send("portal",region) end)
					b.Name="Portal"..region
					b.TextScaled=true
					make("UITextSizeConstraint",b,{MinTextSize=11,MaxTextSize=12})
					if con.portal==region then b.BackgroundColor3=mint b.TextColor3=deep end
				end
			end
		end or nil})
	for _,id in ipairs(Data.FurnitureOrder) do
		local f=Data.Furniture[id]
		if f.hotspot==h.id then
			local costs,funded=costLine(f.costs)
			local levelOk=carpentry>=f.level
			local reason=if current then "Remove the current piece first." elseif not levelOk then "Requires Carpentry "..f.level.."." elseif not funded then "Gather the materials first." else nil
			card({name="Plan"..id,motif="Workshop",title=escape(f.name),titleColor=levelOk and ivory or muted,
				subtitle=(levelOk and check or cross).." Carpentry "..f.level.."  ·  +"..fmt(f.xp).." XP",
				badge=currentId==id and "BUILT" or nil,badgeColor=mint,detail=escape(f.text),lines={costs},
				actions={{caption="Build",primary=reason==nil,disabled=reason~=nil,reason=reason,fn=function() send("build",h.id..":"..id) end}}})
		end
	end
end
Pages.drawQuests,Pages.drawDiaries,Pages.drawConstruction=drawQuests,drawDiaries,drawConstruction
Pages.resetJournal=function() QJ.lampFor=nil QJ.removeFor=nil end
end

------------------------------------------------------------------------------
-- Hero: skills, gear, enchanting, accessories, pets
------------------------------------------------------------------------------
do
local selectedSkill
local function skillUnlocks(skill,level)
	local list={}
	local function add(at,text,item)
		if num(at,0)>level then table.insert(list,{level=at,text=text,item=item}) end
	end
	if not Data then return list end
	for _,resource in ipairs(tbl(tbl(Data.ResourceTiers)[skill])) do
		local tool=num(resource.tool,0)>0 and (", tier "..resource.tool.." "..string.lower(tostring(tbl(Data.ToolKind)[skill] or "tool"))) or ""
		add(resource.level,"Gather "..escape(resource.name).." (+"..fmt(resource.xp).." XP"..tool..")",resource.id)
	end
	for id,recipe in pairs(tbl(Data.Recipes)) do
		if recipe.skill==skill then add(recipe.level,"Craft "..escape(itemName(recipe.output)).." at the "..escape(recipe.station or "station"),recipe.output) end
	end
	for id,def in pairs(tbl(Data.Items)) do
		local need=type(def.requires)=="table" and num(def.requires[skill],nil)
		if need and (def.kind=="weapon" or def.kind=="armor" or def.kind=="tool") then
			add(need,(def.kind=="tool" and "Wield " or "Equip ")..escape(def.name),id)
		end
	end
	for _,region in ipairs(tbl(Data.Regions)) do
		local need=num(tbl(tbl(region.requires).skills)[skill],nil)
		if need then add(need,"Enter "..escape(region.name),nil) end
	end
	if skill=="Enchanting" then
		for _,enchant in pairs(tbl(Data.Enchants)) do add(enchant.level,"Learn "..escape(enchant.name).." I",nil) end
	end
	local bag=tbl(Data.AccessoryBag)
	if skill==tbl(bag.slotsPerLevel).skill and num(tbl(bag.slotsPerLevel).every,0)>0 then
		local every=bag.slotsPerLevel.every
		add((level//every+1)*every,"+1 accessory bag slot",nil)
	end
	table.sort(list,function(a,b) if a.level~=b.level then return a.level<b.level end return a.text<b.text end)
	return list
end
local function drawSkillDetail(skill,info)
	local def=skillDef(skill)
	local hex=skillHex(skill)
	local lines={}
	if not info.maxed and Data and type(Data.levelCoinReward)=="function" then
		local ok,coins=pcall(Data.levelCoinReward,info.level+1)
		if ok then table.insert(lines,"Next level: "..paint("+"..fmt(coins).." coins","F9CC77").."  "..statText(def.perLevel,1)) end
	end
	if info.level>1 then table.insert(lines,"Earned so far: "..statText(def.perLevel,info.level-1)) end
	card({name="SkillDetail",accent=rgb(hex),icon=function(parent,size) return titleArt(parent,skill,size,"Hero") end,
		title=escape(skill).."  ·  "..escape(def.title or ""),titleColor=rgb(lighten(hex,.25)),
		subtitle="Level "..info.level.." / "..maxLevel().."   ·   "..fmt(info.xp).." XP",badge=info.maxed and "MAXED" or ("Lv "..info.level),
		detail=type(def.description)=="string" and escape(def.description) or nil,lines=lines,
		bar={fraction=info.fraction,color=rgb(hex),caption=info.maxed and "MAX LEVEL" or (fmt(math.max(0,info.ceiling-info.xp)).." XP to level "..(info.level+1))},
		actions={{caption="Close",fn=function() selectedSkill=nil;render() end}}})
	heading(string.upper(skill).."    /    NEXT UNLOCKS")
	local unlocks=skillUnlocks(skill,info.level)
	if #unlocks==0 then
		card({motif="Hero",title="Mastered",detail="Every recorded unlock for "..escape(skill).." is already yours."})
		return
	end
	for i=1,math.min(8,#unlocks) do
		local unlock=unlocks[i]
		card({name="Unlock"..i,item=unlock.item,motif=unlock.item==nil and "Hero" or nil,iconSize=compactAtlas and 30 or 36,title=unlock.text,
			badge="Lv "..unlock.level,badgeColor=rgb(lighten(hex,.3))})
	end
	if #unlocks>8 then para(container(),"…and "..(#unlocks-8).." more unlocks further along the "..escape(skill).." path.",1,muted) end
end
local function drawSkills()
	local levels=skillsOf(state)
	local skills=skillOrder()
	local d=depth()
	local total,average=0,0
	for _,skill in ipairs(skills) do total+=levels[skill].level end
	average=#skills>0 and total/#skills or 0
	if d then total=num(d.totalLevel,total);average=num(d.skillAverage,average) end
	card({name="SkillSummary",motif="Hero",title="Total level "..fmt(total),titleColor=gold,
		subtitle="Skill average "..string.format("%.1f",average).."   ·   "..#skills.." skills",
		badge=if d then nil else "SYNCING",badgeColor=muted,
		detail="Every level grants permanent stats and coins. Tap a skill to see what unlocks next."})
	if selectedSkill and levels[selectedSkill] then drawSkillDetail(selectedSkill,levels[selectedSkill]) heading("ALL SKILLS") end
	local width=contentWidth()
	local columns=width>=690 and 3 or (width>=400 and 2 or 1)
	local cellHeight=compactAtlas and 100 or 110
	local grid=gridHolder(UDim2.new(1/columns,-6,0,cellHeight),6)
	for i,skill in ipairs(skills) do
		local info=levels[skill]
		local hex=skillHex(skill)
		local color=rgb(hex)
		local tileButton=tile(grid,"Skill"..skill,i,function()
			selectedSkill=if selectedSkill==skill then nil else skill
			scroll.CanvasPosition=Vector2.zero
			render()
		end)
		make("UIStroke",tileButton,{Color=selectedSkill==skill and gold or color,Transparency=selectedSkill==skill and 0 or .55,Thickness=selectedSkill==skill and 2 or 1})
		local accent=make("Frame",tileButton,{Position=UDim2.fromOffset(0,10),Size=UDim2.new(0,4,1,-20),BackgroundColor3=color,BorderSizePixel=0})
		make("UICorner",accent,{CornerRadius=UDim.new(0,2)})
		local nameText=label(tileButton,skill,12,compactAtlas and 5 or 7,UDim.new(1,-80),20,bold,compactAtlas and 13 or 15,ivory)
		local levelText=label(tileButton,info.maxed and "MAX" or (info.level.." / "..maxLevel()),0,compactAtlas and 5 or 7,UDim.new(0,70),20,bold,compactAtlas and 12 or 14,rgb(lighten(hex,.3)))
		levelText.Position=UDim2.new(1,-78,0,compactAtlas and 5 or 7)
		levelText.TextXAlignment=Enum.TextXAlignment.Right
		local reward=label(tileButton,statText(skillDef(skill).perLevel,1).." "..paint("/ level","BECECA"),12,compactAtlas and 25 or 29,UDim.new(1,-20),compactAtlas and 30 or 28,regular,compactAtlas and 10 or 11,muted)
		reward.RichText=true
		reward.TextWrapped=true
		reward.TextYAlignment=Enum.TextYAlignment.Top
		local bar=progress(tileButton,info.fraction,color,nil,compactAtlas and 10 or 12)
		bar.Position=UDim2.new(0,12,0,compactAtlas and 60 or 63)
		bar.Size=UDim2.new(1,-22,0,compactAtlas and 10 or 12)
		local remaining=info.maxed and (fmt(info.xp).." XP  ·  mastered") or (fmt(math.max(0,info.ceiling-info.xp)).." XP to "..(info.level+1).."  ·  "..math.floor(info.fraction*1000+.5)/10 .."%")
		label(tileButton,remaining,12,compactAtlas and 76 or 82,UDim.new(1,-20),16,regular,compactAtlas and 10 or 11,muted)
	end
end

local selectedSlot="weapon"
local function drawStatSheet(stats)
	local keys={}
	for _,key in ipairs(Data and Data.StatOrder or {}) do table.insert(keys,key) end
	for _,key in ipairs({"effectiveHealth","damage","magicalPower","combatBonus"}) do table.insert(keys,key) end
	local width=contentWidth()
	local columns=width>=600 and 3 or (width>=340 and 2 or 1)
	local grid=gridHolder(UDim2.new(1/columns,-6,0,compactAtlas and 28 or 32),5)
	for i,key in ipairs(keys) do
		local value=num(stats[key],nil)
		if value then
			local def=statDef(key)
			local chip=make("Frame",grid,{Name="Stat"..key,BackgroundColor3=deep,BorderSizePixel=0,LayoutOrder=i})
			make("UICorner",chip,{CornerRadius=UDim.new(0,8)})
			make("UIStroke",chip,{Color=slate,Transparency=.35,Thickness=1})
			local symbol=label(chip,def.symbol or "•",6,0,UDim.new(0,20),0,bold,compactAtlas and 13 or 15,rgb(lighten(def.color or "FFFFFF",.15)))
			symbol.Size=UDim2.new(0,20,1,0)
			symbol.TextXAlignment=Enum.TextXAlignment.Center
			local name=label(chip,def.name or key,28,0,UDim.new(1,-96),0,regular,compactAtlas and 11 or 12,muted)
			name.Size=UDim2.new(1,-96,1,0)
			local amount=label(chip,statValue(key,value),0,0,UDim.new(0,64),0,bold,compactAtlas and 12 or 14,ivory)
			amount.Position=UDim2.new(1,-70,0,0)
			amount.Size=UDim2.new(0,64,1,0)
			amount.TextXAlignment=Enum.TextXAlignment.Right
		end
	end
end
local function setSummary(stats,equipment)
	local sets=Data and tbl(Data.Sets) or EMPTY
	local active=type(stats.activeSet)=="string" and sets[stats.activeSet]
	if type(active)=="table" then
		card({name="SetBonus",motif="Hero",accent=safeColor(active.color,gold),title=escape(active.name or stats.activeSet).." set bonus",titleColor=gold,badge="4 / 4",
			detail="Active: "..escape(active.text or "")})
		return
	end
	local counts={}
	for _,slot in ipairs(gearSlots) do
		local def=itemDef(equipment[slot])
		if def and def.set then counts[def.set]=(counts[def.set] or 0)+1 end
	end
	local best,bestCount
	for setId,n in pairs(counts) do if not bestCount or n>bestCount then best,bestCount=setId,n end end
	if best and type(sets[best])=="table" then
		card({name="SetBonus",motif="Hero",title=escape(sets[best].name or best).." set",badge=bestCount.." / 4",badgeColor=muted,
			detail="Wear all four pieces for: "..escape(sets[best].text or "a set bonus").."."})
	end
end
local function drawGear()
	if not Data then dataMissing() return end
	local d=depth()
	if not d then
		syncing("stat sheet and equipment")
		if type(state.stats)=="table" then row("Vitality & armor",tostring(state.stats.maxHealth or "?").." max health   /   "..tostring(state.stats.defense or 0).." defense") end
		return
	end
	local stats=tbl(d.stats)
	local equipment=tbl(d.equipment)
	local levels=skillsOf(state)
	heading("STAT SHEET")
	drawStatSheet(stats)
	setSummary(stats,equipment)
	heading("EQUIPMENT")
	local width=contentWidth()
	local tileWidth=math.floor((width-4*6)/5)
	local grid=gridHolder(UDim2.new(.2,-6,0,compactAtlas and 92 or 108),6)
	local iconSize=math.clamp(tileWidth-24,30,compactAtlas and 40 or 52)
	for i,slot in ipairs(gearSlots) do
		local id=equipment[slot]
		local auto=false
		if slot=="weapon" and not id and type(stats.weapon)=="string" then id=stats.weapon;auto=true end
		local def=itemDef(id)
		local on=selectedSlot==slot
		local slotTile=tile(grid,"Slot"..slot,i,function() selectedSlot=slot;render() end)
		make("UIStroke",slotTile,{Color=on and gold or slate,Transparency=on and 0 or .3,Thickness=on and 2 or 1})
		local art
		if def then art=itemIcon(slotTile,id,iconSize) else art=motif(slotTile,"Hero",iconSize);art.BackgroundTransparency=.4 end
		art.AnchorPoint=Vector2.new(.5,0)
		art.Position=UDim2.new(.5,0,0,6)
		local slotText=label(slotTile,string.upper(slotNames[slot]),0,iconSize+8,full,14,bold,9,mint)
		slotText.TextXAlignment=Enum.TextXAlignment.Center
		local nameText=label(slotTile,def and (auto and (def.name.." (auto)") or def.name) or "Empty",4,iconSize+22,UDim.new(1,-8),30,bold,compactAtlas and 10 or 11,def and rgb(itemHex(id)) or muted)
		nameText.TextXAlignment=Enum.TextXAlignment.Center
		nameText.TextWrapped=true
	end
	-- Selected slot detail and candidates.
	local id=equipment[selectedSlot]
	local def=itemDef(id)
	if def then
		local enchants={}
		for enchantId,level in pairs(tbl(tbl(dget("enchants"))[id])) do
			local enchant=tbl(Data.Enchants)[enchantId]
			table.insert(enchants,escape((type(enchant)=="table" and enchant.name or enchantId).." "..numeral(num(level,1))))
		end
		table.sort(enchants)
		card({name="Equipped"..selectedSlot,item=id,title=escape(def.name),titleColor=rgb(itemHex(id)),subtitle=escape(def.rarity.." "..kindLabel(def)),badge="EQUIPPED",badgeColor=mint,
			detail=statText(def.stats),lines={#enchants>0 and paint("Enchanted: "..table.concat(enchants,", "),"7FD3E3") or nil,def.set and Data.Sets[def.set] and ("Set: "..escape(Data.Sets[def.set].name).." — "..escape(Data.Sets[def.set].text)) or nil},
			actions={{caption="Enchant",fn=function() enchantTarget=id;sectionOf.Hero="Enchant";scroll.CanvasPosition=Vector2.zero;render() end},
				{caption="Unequip",fn=function() send("unequip",selectedSlot) end}}})
	end
	local candidates={}
	for itemId,n in pairs(tbl(state.items)) do
		local candidate=itemDef(itemId)
		if num(n,0)>0 and candidate and candidate.slot==selectedSlot and itemId~=id then table.insert(candidates,itemId) end
	end
	table.sort(candidates,function(a,b)
		local da,db=itemDef(a),itemDef(b)
		if num(da.tier,0)~=num(db.tier,0) then return num(da.tier,0)>num(db.tier,0) end
		return da.name<db.name
	end)
	heading("OWNED  "..string.upper(slotNames[selectedSlot]).."  GEAR")
	if #candidates==0 then
		card({motif="Workshop",title=def and "No other "..string.lower(slotNames[selectedSlot]).." gear" or "Nothing to equip here",
			detail="Forge "..string.lower(slotNames[selectedSlot]).." gear at the Forge, or find it on your travels."})
	end
	for _,candidateId in ipairs(candidates) do
		local candidate=itemDef(candidateId)
		local ok,requirements=meetsRequires(candidate.requires,levels)
		card({name="Equip"..candidateId,item=candidateId,title=escape(candidate.name),titleColor=rgb(itemHex(candidateId)),subtitle=escape(candidate.rarity.." "..kindLabel(candidate)),
			detail=statText(candidate.stats),lines={requirements~="" and ("Requires "..requirements) or nil},
			actions={{caption="Equip",disabled=not ok,reason="Requires "..(requirements:gsub("<[^>]+>","")),fn=function() send("equip",candidateId) end}}})
	end
	-- Gathering tools (auto-selected best tool per skill).
	heading("GATHERING TOOLS")
	local tools=tbl(d.tools)
	local toolGrid=gridHolder(UDim2.new(width>=440 and .5 or 1,-6,0,compactAtlas and 60 or 62),6)
	for i,skill in ipairs({"Mining","Woodcutting","Fishing","Farming"}) do
		local toolId=tools[skill]
		local toolDef=itemDef(toolId)
		local toolTile=tile(toolGrid,"Tool"..skill,i,function()
			if toolDef then enchantTarget=toolId;sectionOf.Hero="Enchant";scroll.CanvasPosition=Vector2.zero;render() end
		end)
		make("UIStroke",toolTile,{Color=rgb(skillHex(skill)),Transparency=.5,Thickness=1})
		local size=compactAtlas and 38 or 44
		local art=toolDef and itemIcon(toolTile,toolId,size) or motif(toolTile,"Workshop",size)
		art.Position=UDim2.fromOffset(8,(compactAtlas and 60 or 62)/2-size/2)
		label(toolTile,skill,size+16,compactAtlas and 5 or 7,UDim.new(1,-size-22),16,bold,11,rgb(lighten(skillHex(skill),.3)))
		local toolName=label(toolTile,toolDef and toolDef.name or "Bare hands",size+16,compactAtlas and 22 or 23,UDim.new(1,-size-22),18,bold,compactAtlas and 12 or 13,toolDef and rgb(itemHex(toolId)) or muted)
		local fortune=toolDef and tbl(toolDef.stats)[tbl(Data.FortuneStat)[skill]]
		local tierText=toolDef and ("Tier "..num(toolDef.toolTier,1)..(fortune and ("  ·  +"..fmt(fortune).." ☘") or "")) or "Craft one at the Forge"
		label(toolTile,tierText,size+16,compactAtlas and 41 or 42,UDim.new(1,-size-22),14,regular,11,muted)
	end
	-- Active timed effects.
	local buffs={}
	for buffId,buff in pairs(tbl(d.buffs)) do if type(buff)=="table" then table.insert(buffs,buffId) end end
	if #buffs>0 then
		table.sort(buffs)
		heading("ACTIVE EFFECTS")
		for _,buffId in ipairs(buffs) do
			local buff=d.buffs[buffId]
			card({name="Buff"..buffId,item=buffId,title=escape(itemName(buffId)),titleColor=rgb(itemHex(buffId)),badge=clock(buff.remaining),badgeColor=mint,detail=statText(buff.stats)})
		end
	end
end

local function drawEnchant()
	if not Data or type(Data.Enchants)~="table" then dataMissing() return end
	local d=depth()
	if not d then syncing("enchantments") return end
	local candidates={}
	for id,n in pairs(tbl(state.items)) do
		if num(n,0)>0 and enchantKind(itemDef(id)) then table.insert(candidates,id) end
	end
	table.sort(candidates,function(a,b)
		local ea,eb=equippedSlotOf(a)~=nil,equippedSlotOf(b)~=nil
		if ea~=eb then return ea end
		local ra,rb=rarityRank(itemDef(a).rarity),rarityRank(itemDef(b).rarity)
		if ra~=rb then return ra>rb end
		return itemDef(a).name<itemDef(b).name
	end)
	local levels=skillsOf(state)
	local enchanting=levels.Enchanting and levels.Enchanting.level or 1
	card({name="EnchantSummary",motif="Journal",title="Runesmith's table",titleColor=gold,subtitle="Enchanting "..enchanting.."  ·  "..fmt(count("items","ArcaneDust")).." Arcane Dust  ·  "..fmt(state.coins).." coins",
		detail="Each enchant level costs Arcane Dust and coins, needs an Enchanting level and grants Enchanting XP."})
	if #candidates==0 then
		card({motif="Workshop",title="Nothing to enchant",detail="Forge or find a weapon, armor piece or tool first."})
		return
	end
	if not table.find(candidates,enchantTarget) then enchantTarget=candidates[1] end
	heading("CHOOSE AN ITEM")
	local size=compactAtlas and 54 or 62
	local grid=gridHolder(UDim2.fromOffset(size,size),6)
	for i,id in ipairs(candidates) do
		local on=id==enchantTarget
		local pick=tile(grid,"Enchant"..id,i,function() enchantTarget=id;render() end)
		make("UIStroke",pick,{Color=on and gold or slate,Transparency=on and 0 or .4,Thickness=on and 2 or 1})
		local art=itemIcon(pick,id,size-12)
		art.Position=UDim2.fromOffset(6,6)
		if equippedSlotOf(id) then
			local mark=label(pick,"E",0,2,UDim.new(0,14),14,bold,11,gold)
			mark.Position=UDim2.new(1,-14,0,2)
		end
	end
	local id=enchantTarget
	local def=itemDef(id)
	local kind=enchantKind(def)
	local applied=tbl(tbl(dget("enchants"))[id])
	heading(string.upper(def.name).."    /    ENCHANTMENTS")
	local enchantIds={}
	for enchantId,enchant in pairs(Data.Enchants) do if type(enchant)=="table" and enchant.appliesTo==kind then table.insert(enchantIds,enchantId) end end
	table.sort(enchantIds,function(a,b)
		local la,lb=num(Data.Enchants[a].level,1),num(Data.Enchants[b].level,1)
		if la~=lb then return la<lb end
		return a<b
	end)
	for _,enchantId in ipairs(enchantIds) do
		local enchant=Data.Enchants[enchantId]
		local have=num(applied[enchantId],0)
		local maxEnchant=num(enchant.maxLevel,1)
		local labels={}
		for i=1,maxEnchant do labels[i]=numeral(i) end
		if have>=maxEnchant then
			card({name="Ench"..enchantId,motif="Journal",title=escape(enchant.name).." "..numeral(have),titleColor=rgb("7FD3E3"),badge="MAXED",badgeColor=mint,
				detail=escape(enchant.description or ""),pips={total=maxEnchant,filled=have,color=rgb("4FB0C6"),labels=labels}})
		else
			local nextLevel=have+1
			local okCost,cost=pcall(Data.enchantCost,nextLevel)
			cost=okCost and tbl(cost) or EMPTY
			local okGate,gate=pcall(Data.enchantSkillLevel,enchant,nextLevel)
			gate=okGate and num(gate,1) or num(enchant.level,1)
			local okXp,xp=pcall(Data.enchantXp,nextLevel)
			local parts,affordable={},true
			local costIds={}
			for costId in pairs(cost) do if costId~="coins" then table.insert(costIds,costId) end end
			table.sort(costIds)
			for _,costId in ipairs(costIds) do
				local need=num(cost[costId],0)
				local held=count("items",costId)
				if held<need then affordable=false end
				table.insert(parts,paint(fmt(held).."/"..fmt(need),held>=need and "9EE7D2" or "E8806A").." "..escape(itemName(costId)))
			end
			local coins=num(cost.coins,0)
			if coins>0 then
				if num(state.coins,0)<coins then affordable=false end
				table.insert(parts,paint(fmt(coins).." coins",num(state.coins,0)>=coins and "F9CC77" or "E8806A"))
			end
			local gateOk=enchanting>=gate
			local reason=not gateOk and ("Requires Enchanting "..gate..".") or (not affordable and "You cannot afford this enchant yet.") or nil
			card({name="Ench"..enchantId,motif="Journal",title=escape(enchant.name).." "..numeral(nextLevel),titleColor=rgb("7FD3E3"),
				subtitle=have>0 and ("Currently "..numeral(have).." of "..numeral(maxEnchant)) or ("Not applied  ·  max "..numeral(maxEnchant)),
				badge=(gateOk and check or cross).." Lv "..gate,badgeColor=ivory,
				detail=escape(enchant.description or ""),
				lines={"Cost: "..table.concat(parts,"  ·  "),okXp and ("+"..fmt(xp).." Enchanting XP") or nil},
				pips={total=maxEnchant,filled=have,color=rgb("4FB0C6"),labels=labels},
				actions={{caption="Enchant",primary=reason==nil,disabled=reason~=nil,reason=reason,fn=function() send("enchantItem",id..":"..enchantId) end}}})
		end
	end
end

local function drawAccessories()
	if not Data then dataMissing() return end
	local d=depth()
	if not d then syncing("accessory bag") return end
	local bag,active={}, {}
	for _,id in ipairs(tbl(d.accessoryBag)) do bag[id]=true end
	local activeCount=0
	for _,id in ipairs(tbl(d.activeAccessories)) do active[id]=true;activeCount+=1 end
	local slots=num(d.accessorySlots,0)
	local inBag=0
	for _ in pairs(bag) do inBag+=1 end
	local power=num(tbl(d.stats).magicalPower,0)
	local rule=tbl(Data.AccessoryBag)
	local every=num(tbl(rule.slotsPerLevel).every,5)
	card({name="AccessoryBag",motif="Satchel",title="Accessory bag",titleColor=gold,subtitle=fmt(inBag).." in bag  ·  "..fmt(activeCount).." active",
		badge=activeCount.." / "..slots,
		detail=paint("✧ Magical Power "..fmt(power),"FFAA00").."  grants "..statText({health=power,strength=math.floor(power/4)})..".",
		lines={"Duplicates do not stack; highest rarity fills slots first. +1 slot every "..every.." "..tostring(tbl(rule.slotsPerLevel).skill or "Combat").." levels (max "..num(rule.maxSlots,24)..")."},
		bar={fraction=slots>0 and activeCount/slots or 0,color=gold,caption=activeCount.." / "..slots.." slots"}})
	local owned,missing={},{}
	for id,def in pairs(tbl(Data.Items)) do
		if type(def)=="table" and def.kind=="accessory" then
			if count("items",id)>0 or bag[id] then table.insert(owned,id) else table.insert(missing,id) end
		end
	end
	local function byRarity(a,b)
		local ra,rb=rarityRank(itemDef(a).rarity),rarityRank(itemDef(b).rarity)
		if ra~=rb then return ra>rb end
		return itemDef(a).name<itemDef(b).name
	end
	table.sort(owned,byRarity)
	table.sort(missing,byRarity)
	heading("YOUR ACCESSORIES    /    TAP TO TOGGLE")
	if #owned==0 then card({motif="Satchel",title="No accessories yet",detail="Craft talismans at the Workbench once their collections unlock."}) end
	local width=contentWidth()
	local grid=gridHolder(UDim2.new(width>=440 and .5 or 1,-6,0,compactAtlas and 56 or 64),6)
	for i,id in ipairs(owned) do
		local def=itemDef(id)
		local isActive,isBagged=active[id]==true,bag[id]==true
		local entry=tile(grid,"Accessory"..id,i,function() send("accessory",id) end)
		make("UIStroke",entry,{Color=isActive and mint or (isBagged and gold or slate),Transparency=isActive and .1 or .35,Thickness=isActive and 2 or 1})
		local size=compactAtlas and 40 or 46
		local art=itemIcon(entry,id,size)
		art.Position=UDim2.new(0,6,.5,-size/2)
		label(entry,def.name,size+14,compactAtlas and 5 or 7,UDim.new(1,-size-90),18,bold,compactAtlas and 12 or 13,rgb(itemHex(id)))
		local power=tbl(tbl(Data.Rarity)[def.rarity]).power
		local statsLine=label(entry,statText(def.stats,1,"  "),size+14,compactAtlas and 24 or 28,UDim.new(1,-size-20),16,regular,compactAtlas and 10 or 11,muted)
		statsLine.RichText=true
		local status=label(entry,isActive and "ACTIVE" or (isBagged and "NO SLOT" or "ADD"),0,compactAtlas and 5 or 7,UDim.new(0,70),18,bold,10,isActive and mint or (isBagged and gold or muted))
		status.Position=UDim2.new(1,-76,0,compactAtlas and 5 or 7)
		status.TextXAlignment=Enum.TextXAlignment.Right
		if power then
			local mp=label(entry,"✧ "..power,0,compactAtlas and 38 or 44,UDim.new(0,70),14,bold,10,rgb("FFAA00"))
			mp.Position=UDim2.new(1,-76,0,compactAtlas and 38 or 44)
			mp.TextXAlignment=Enum.TextXAlignment.Right
		end
	end
	if #missing>0 then
		heading("UNDISCOVERED    /    "..#missing.." TO CRAFT")
		local names={}
		for _,id in ipairs(missing) do
			local recipe=tbl(Data.Recipes)[id]
			local gate={}
			for gateId,tier in pairs(tbl(type(recipe)=="table" and recipe.collectionTier)) do table.insert(gate,itemName(gateId).." "..numeral(tier)) end
			table.insert(names,paint(escape(itemName(id)),rarityHex(itemDef(id).rarity))..(#gate>0 and paint(" ("..escape(table.concat(gate,", "))..")","BECECA") or ""))
		end
		card({motif="Workshop",title="Workbench patterns",detail=table.concat(names,"  ·  "),lines={"Unlock each pattern through its collection, then craft it at the Workbench."}})
	end
end

local function petSources()
	local sources={}
	if not Data then return sources end
	local list={}
	for _,monster in pairs(tbl(Data.Monsters)) do table.insert(list,monster) end
	for _,monster in pairs(tbl(Data.SeaCreatures)) do table.insert(list,monster) end
	for _,monster in ipairs(list) do
		for _,drop in ipairs(tbl(monster.drops)) do
			if type(drop)=="table" then
				sources[drop.item]=sources[drop.item] or {}
				table.insert(sources[drop.item],tostring(monster.name).." ("..chance(drop.chance)..")")
			end
		end
	end
	for _,slayer in pairs(tbl(Data.Slayers)) do
		for tierIndex,tierDef in ipairs(tbl(slayer.tiers)) do
			for _,drop in ipairs(tbl(tierDef.drops)) do
				if type(drop)=="table" then
					sources[drop.item]=sources[drop.item] or {}
					table.insert(sources[drop.item],tostring(slayer.name).." "..numeral(tierIndex).." ("..chance(drop.chance)..")")
				end
			end
		end
	end
	for _,list in pairs(sources) do table.sort(list) end
	return sources
end
local function drawPets()
	if not Data then dataMissing() return end
	local d=depth()
	-- Pet items can be adopted even before the Depth record arrives.
	local adoptable={}
	for id,n in pairs(tbl(state.items)) do
		local def=itemDef(id)
		if num(n,0)>0 and def and def.kind=="pet" then table.insert(adoptable,id) end
	end
	table.sort(adoptable)
	if #adoptable>0 then
		heading("READY TO ADOPT")
		for _,id in ipairs(adoptable) do
			local def=itemDef(id)
			local pet=tbl(tbl(Data.PetById)[def.pet])
			card({name="Adopt"..id,item=id,title=escape(def.name).."  ×"..count("items",id),titleColor=rgb(itemHex(id)),subtitle=escape(def.rarity.." · "..tostring(pet.skill or "").." companion"),
				detail=escape(pet.ability or def.description or ""),actions={{caption="Adopt",primary=true,fn=function() send("petAdopt",id) end}}})
		end
	end
	if not d then syncing("pet roster") return end
	local pets=tbl(d.pets)
	local ownedKinds={}
	heading("COMPANIONS    /    "..#pets.." OWNED")
	if #pets==0 then card({motif="Co-op",title="No companions yet",detail="Rare creature drops and slayer bosses yield pet items. Adopt them here."}) end
	for index,pet in ipairs(pets) do
		if type(pet)=="table" then
			local def=tbl(tbl(Data.PetById)[pet.id])
			ownedKinds[pet.id]=true
			local level=num(pet.level,1)
			local xp=num(pet.xp,0)
			local nextXp=num(pet.next,nil)
			if not nextXp and type(Data.petXpToNext)=="function" then
				local ok,value=pcall(Data.petXpToNext,level,def.rarity or "Common")
				nextXp=ok and num(value,nil) or nil
			end
			local maxed=level>=num(Data.PET_MAX_LEVEL,100)
			local isActive=pet.active==true
			local hex=rarityHex(def.rarity or "Common")
			card({name="Pet"..index,item=tostring(pet.id).."Pet",title=escape(def.name or pet.id or "Pet"),titleColor=rgb(hex),edge=isActive and mint or nil,
				subtitle="Lv "..level.."  ·  "..escape((def.rarity or "").." "..tostring(def.skill or "")).." pet",badge=isActive and "SUMMONED" or nil,badgeColor=mint,
				detail=paint(escape(def.ability or ""),"F9CC77"),lines={statText(def.perLevel,level)},
				bar={fraction=maxed and 1 or ((nextXp and nextXp>0) and xp/nextXp or 0),color=rgb(hex),caption=maxed and "MAX LEVEL" or (nextXp and (short(xp).." / "..short(nextXp).." XP") or (short(xp).." XP"))},
				actions={isActive and {caption="Dismiss",fn=function() send("petSummon","0") end} or {caption="Summon",primary=true,fn=function() send("petSummon",tostring(index)) end}}})
		end
	end
	local sources=petSources()
	local missing={}
	for _,pet in ipairs(tbl(Data.Pets)) do if type(pet)=="table" and not ownedKinds[pet.id] then table.insert(missing,pet) end end
	if #missing>0 then
		heading("PET COMPENDIUM")
		for _,pet in ipairs(missing) do
			local from=sources[pet.id.."Pet"]
			card({name="Compendium"..pet.id,locked=true,title=escape(pet.name),titleColor=muted,subtitle=escape(tostring(pet.rarity).." "..tostring(pet.skill)).." pet",
				detail=escape(pet.ability or ""),lines={from and ("Found from: "..escape(table.concat(from,", "))) or "Source unknown."}})
		end
	end
end

Pages.drawSkills,Pages.drawGear,Pages.drawEnchant,Pages.drawAccessories,Pages.drawPets=drawSkills,drawGear,drawEnchant,drawAccessories,drawPets
end

------------------------------------------------------------------------------
-- Satchel: rarity grid inventory with item detail, collections
------------------------------------------------------------------------------
do
local satchelFilter="All"
local selectedItem
local filterKinds={Gear={weapon=true,armor=true},Tools={tool=true},Food={consumable=true},Materials={resource=true,material=true},Trinkets={accessory=true,pet=true}}
local function itemDetail(id)
	local def=itemDef(id)
	local n=count("items",id)
	local levels=skillsOf(state)
	local lines={}
	local actions={}
	local d=depth()
	local legacy=type(state.consumables)=="table" and state.consumables[id]
	if def then
		if def.stats then table.insert(lines,statText(def.stats)) end
		local enchants={}
		for enchantId,level in pairs(tbl(tbl(dget("enchants"))[id])) do
			local enchant=Data and tbl(Data.Enchants)[enchantId]
			table.insert(enchants,escape((type(enchant)=="table" and enchant.name or enchantId).." "..numeral(num(level,1))))
		end
		if #enchants>0 then table.sort(enchants);table.insert(lines,paint("Enchanted: "..table.concat(enchants,", "),"7FD3E3")) end
		if def.heal then table.insert(lines,"Restores up to "..paint(fmt(def.heal).." ❤ Health","FF6B6B")..(def.recovery and ("  ·  "..def.recovery.."s recovery") or "")) end
		if type(def.buff)=="table" then table.insert(lines,"Buff: "..statText(def.buff.stats).." for "..clock(def.buff.duration)) end
		if def.set and Data and type(tbl(Data.Sets)[def.set])=="table" then table.insert(lines,"Set: "..escape(Data.Sets[def.set].name).." — "..escape(Data.Sets[def.set].text or "")) end
		if def.kind=="pet" then table.insert(lines,paint(escape(tbl(tbl(Data.PetById)[def.pet]).ability or ""),"F9CC77")) end
		if def.kind=="accessory" then table.insert(lines,paint("✧ Magical Power "..tostring(tbl(tbl(Data.Rarity)[def.rarity]).power or "?"),"FFAA00")) end
		local ok,requirements=meetsRequires(def.requires,levels)
		if requirements~="" then table.insert(lines,"Requires "..requirements) end
		-- Skip flavour copy that only repeats the requirement line above it.
		if type(def.description)=="string" and not (requirements~="" and def.description:match("^Requires")) then table.insert(lines,escape(def.description)) end
		table.insert(lines,paint("Sells for "..fmt(def.value).." coins each  ·  "..fmt(num(def.value,0)*n).." for the stack","F9CC77"))
		-- Actions per kind.
		local slot=def.slot
		if gearSlotSet[slot] then
			local equippedSlot=equippedSlotOf(id)
			if equippedSlot then table.insert(actions,{caption="Unequip",fn=function() send("unequip",equippedSlot) end})
			else table.insert(actions,{caption="Equip",primary=ok,disabled=not ok or not d,reason=not d and "Your gear record is still syncing." or ("Requires "..requirements:gsub("<[^>]+>","")),fn=function() send("equip",id) end}) end
		end
		if def.kind=="consumable" then
			if legacy then
				table.insert(actions,{caption=tostring(legacy.action or "Use"),primary=true,fn=function() send("heal",id) end})
			else
				table.insert(actions,{caption=def.category=="food" and "Eat" or "Drink",primary=true,fn=function() send("consume",id) end})
			end
		elseif def.kind=="accessory" then
			local bagged=table.find(tbl(d and d.accessoryBag),id)~=nil
			table.insert(actions,{caption=bagged and "Remove" or "Add",fn=function() send("accessory",id) end})
		elseif def.kind=="pet" then
			table.insert(actions,{caption="Adopt",primary=true,fn=function() send("petAdopt",id) end})
		end
		if enchantKind(def) then
			table.insert(actions,{caption="Enchant",fn=function() enchantTarget=id;current="Hero";sectionOf.Hero="Enchant";scroll.CanvasPosition=Vector2.zero;render() end})
		end
	elseif legacy then
		table.insert(lines,"Restores up to "..tostring(legacy.healing).." health.")
		table.insert(actions,{caption=tostring(legacy.action or "Use"),fn=function() send("heal",id) end})
	end
	if legacy and num(legacy.readyIn,0)>0 then table.insert(lines,paint("Recovering: ready in "..math.ceil(legacy.readyIn).."s","F9CC77")) end
	if def then
		if sellConfirm==id then
			table.insert(lines,paint("Tap Confirm to sell all "..fmt(n).." for "..fmt(num(def.value,0)*n).." coins"..(equippedSlotOf(id) and " (including the equipped piece)" or "")..".","F9CC77"))
			table.insert(actions,{caption="Confirm",fn=function() sellConfirm=nil;send("sell",id) end})
		else
			table.insert(actions,{caption="Sell",fn=function() sellConfirm=id;render() end})
		end
	end
	local equipped=equippedSlotOf(id)
	card({name="ItemDetail",item=id,iconSize=compactAtlas and 42 or 54,title=escape(def and def.name or id),titleColor=rgb(itemHex(id)),
		subtitle=escape((def and def.rarity or "Common").." "..kindLabel(def)).."  ·  ×"..fmt(n),badge=equipped and "EQUIPPED" or nil,badgeColor=mint,
		lines=lines,actions=actions})
end
local function drawItems()
	local keys={}
	for key,value in pairs(tbl(state.items)) do if num(value,0)>0 then table.insert(keys,key) end end
	heading("SATCHEL    /    "..#keys.." STACKS")
	if #keys==0 then
		row("Your satchel is empty", "Use a gathering prompt to collect your first resource.")
		return
	end
	sectionBar({"All","Gear","Tools","Food","Materials","Trinkets"},satchelFilter,function(name)
		satchelFilter=name;sellConfirm=nil;render()
	end,{small=true,prefix="Filter",maxPer=6})
	local kinds=filterKinds[satchelFilter]
	local shown={}
	local worth=0
	for _,key in ipairs(keys) do
		local def=itemDef(key)
		worth+=num(def and def.value,0)*count("items",key)
		if not kinds or (def and kinds[def.kind]) or (not def and satchelFilter=="Materials") then table.insert(shown,key) end
	end
	table.sort(shown,function(a,b)
		local da,db=itemDef(a),itemDef(b)
		local ra,rb=rarityRank(da and da.rarity),rarityRank(db and db.rarity)
		if ra~=rb then return ra>rb end
		local na,nb=da and da.name or a,db and db.name or b
		return na<nb
	end)
	if selectedItem and count("items",selectedItem)<=0 then selectedItem=nil;sellConfirm=nil end
	if selectedItem then itemDetail(selectedItem) end
	if #shown==0 then
		card({motif="Satchel",title="Nothing in this pocket",detail="Try another filter."})
		return
	end
	local size=compactAtlas and 56 or 66
	local grid=gridHolder(UDim2.fromOffset(size,size),6)
	for i,id in ipairs(shown) do
		local on=id==selectedItem
		local slotTile=tile(grid,"Item"..id,i,function()
			if selectedItem==id then selectedItem=nil else selectedItem=id end
			sellConfirm=nil
			scroll.CanvasPosition=Vector2.zero
			render()
		end)
		make("UIStroke",slotTile,{Color=on and gold or slate,Transparency=on and 0 or .5,Thickness=on and 2 or 1})
		local art=itemIcon(slotTile,id,size-10)
		art.Position=UDim2.fromOffset(5,5)
		local n=count("items",id)
		if n>1 then
			local amount=label(slotTile,short(n),0,0,UDim.new(1,-6),16,bold,11,ivory)
			amount.Position=UDim2.new(0,0,1,-17)
			amount.TextXAlignment=Enum.TextXAlignment.Right
			amount.TextStrokeTransparency=.2
			amount.TextStrokeColor3=deep
		end
		if equippedSlotOf(id) then
			local mark=label(slotTile,"E",5,3,UDim.new(0,14),14,bold,11,gold)
			mark.TextStrokeTransparency=.2
			mark.TextStrokeColor3=deep
		end
	end
	para(container(),"Satchel value "..paint(fmt(worth).." coins","F9CC77").."  ·  tap an item for details and actions.",1,muted)
end

local collectionGroup="Mining"
local unlocksByCollection
local function collectionUnlocks()
	if unlocksByCollection then return unlocksByCollection end
	unlocksByCollection={}
	for recipeId,recipe in pairs(tbl(Data and Data.Recipes)) do
		for itemId,tier in pairs(tbl(type(recipe)=="table" and recipe.collectionTier)) do
			unlocksByCollection[itemId]=unlocksByCollection[itemId] or {}
			local byTier=unlocksByCollection[itemId]
			byTier[tier]=byTier[tier] or {}
			table.insert(byTier[tier],recipe.output or recipeId)
		end
	end
	for _,byTier in pairs(unlocksByCollection) do for _,list in pairs(byTier) do table.sort(list,function(a,b) return itemName(a)<itemName(b) end) end end
	return unlocksByCollection
end
local function collectionItems(group)
	local list={}
	if not Data then return list end
	if group=="Combat" then
		for _,id in ipairs(tbl(Data.CollectionItems)) do if not tbl(Data.ResourceSkill)[id] then table.insert(list,id) end end
	else
		for _,resource in ipairs(tbl(tbl(Data.ResourceTiers)[group])) do table.insert(list,resource.id) end
	end
	return list
end
local function drawCollections()
	if not Data then dataMissing() return end
	if not depth() then para(container(),paint("Syncing live collection tiers… showing your saved totals.","F9CC77"),1,muted) end
	sectionBar({"Mining","Woodcutting","Fishing","Farming","Combat"},collectionGroup,function(name) collectionGroup=name;scroll.CanvasPosition=Vector2.zero;render() end,{small=true,prefix="Collection",maxPer=5})
	local items=collectionItems(collectionGroup)
	local unlocks=collectionUnlocks()
	local maxTier=collectionTierCount()
	local labels={}
	for i=1,maxTier do labels[i]=numeral(i) end
	local discovered,tiers=0,0
	for _,id in ipairs(items) do
		local amount,tier=collectionInfo(id)
		if amount>0 then discovered+=1 end
		tiers+=tier
	end
	heading(string.upper(collectionGroup).."    /    "..discovered.." OF "..#items.." DISCOVERED  ·  "..tiers.." TIERS")
	local groupColor=collectionGroup=="Combat" and rgb("C8553D") or rgb(skillHex(collectionGroup))
	local hidden={}
	for _,id in ipairs(items) do
		local amount,tier,nextAt=collectionInfo(id)
		if amount<=0 then
			table.insert(hidden,id)
		else
			local def=itemDef(id)
			local previous=tier>0 and (collectionThreshold(id,tier) or 0) or 0
			local maxed=tier>=maxTier or not nextAt
			local fraction=maxed and 1 or math.clamp((amount-previous)/math.max(1,nextAt-previous),0,1)
			local lines={}
			local byTier=unlocks[id] or {}
			if not maxed then
				local reward=""
				if type(Data.collectionTierReward)=="function" then
					local ok,value=pcall(Data.collectionTierReward,tier+1)
					if ok and type(value)=="table" and value.coins then reward=paint("+"..fmt(value.coins).." coins","F9CC77") end
				end
				local nextUnlocks={}
				for _,output in ipairs(byTier[tier+1] or {}) do table.insert(nextUnlocks,paint(escape(itemName(output)),itemHex(output))) end
				table.insert(lines,"Tier "..numeral(tier+1).." at "..fmt(nextAt)..": "..reward..(#nextUnlocks>0 and ("  ·  unlocks "..table.concat(nextUnlocks,", ")) or ""))
				if #nextUnlocks==0 then
					for later=tier+2,maxTier do
						if byTier[later] then
							local names={}
							for _,output in ipairs(byTier[later]) do table.insert(names,escape(itemName(output))) end
							table.insert(lines,paint("Tier "..numeral(later).." unlocks "..table.concat(names,", "),"BECECA"))
							break
						end
					end
				end
			end
			local earned={}
			for t=1,tier do for _,output in ipairs(byTier[t] or {}) do table.insert(earned,escape(itemName(output))) end end
			if #earned>0 then
				local shownNames={}
				for i=1,math.min(4,#earned) do shownNames[i]=earned[i] end
				table.insert(lines,paint("Unlocked: "..table.concat(shownNames,", ")..(#earned>4 and (" +"..(#earned-4).." more") or ""),"9EE7D2"))
			end
			card({name="Collection"..id,item=id,title=escape(def and def.name or id),titleColor=rgb(itemHex(id)),
				subtitle=fmt(amount).." collected",badge=tier>0 and ("Tier "..numeral(tier)) or "Tier 0",badgeColor=tier>0 and gold or muted,
				pips={total=maxTier,filled=tier,color=groupColor,labels=labels},
				bar={fraction=fraction,color=gold,caption=maxed and "COLLECTION MAXED" or (fmt(amount).." / "..fmt(nextAt))},lines=lines})
		end
	end
	-- Undiscovered entries share one compact grid of sealed tiles instead of a
	-- column of identical "???" cards.
	if #hidden>0 then
		heading("UNDISCOVERED    /    COLLECT ONCE TO REVEAL")
		local size=compactAtlas and 40 or 46
		local grid=gridHolder(UDim2.fromOffset(size+16,size+30),6)
		for i,id in ipairs(hidden) do
			local cell=make("Frame",grid,{Name="Collection"..id,BackgroundColor3=deep,BorderSizePixel=0,LayoutOrder=i})
			make("UICorner",cell,{CornerRadius=UDim.new(0,10)})
			make("UIStroke",cell,{Color=slate,Transparency=.35,Thickness=1})
			local icon=itemIcon(cell,id,size,true)
			icon.Position=UDim2.new(.5,-size/2,0,7)
			local caption=label(cell,"???",0,size+9,full,16,bold,12,muted)
			caption.TextXAlignment=Enum.TextXAlignment.Center
		end
	end
end

Pages.drawItems,Pages.drawCollections=drawItems,drawCollections
end

------------------------------------------------------------------------------
-- Workshop: station recipe browser, legacy guild patterns, workers, home
------------------------------------------------------------------------------
do
local stationCategory={}
local craftableOnly=false
local categoryOrder={"Ingots","Tools","Weapons","Armor","Meals","Feasts","Potions","Accessories"}
local stationSkills={Forge="Smithing",Hearth="Cooking",Cauldron="Alchemy",Workbench="Carpentry"}
local stationNotes={Forge="Smelt ingots and forge tools, weapons and armor.",Hearth="Cook seared fish and buff feasts.",Cauldron="Brew timed potions.",Workbench="Craft accessories (talismans) for your bag."}
local function recipeStatus(recipe,levels)
	local gates={}
	local ok,reason=true,nil
	local skillLevel=levels[recipe.skill] and levels[recipe.skill].level or 1
	local need=num(recipe.level,1)
	local skillOk=skillLevel>=need
	table.insert(gates,(skillOk and check or cross).." "..escape(tostring(recipe.skill)).." "..need)
	if not skillOk then ok=false;reason="Requires "..tostring(recipe.skill).." "..need.."." end
	local gateIds={}
	for id in pairs(tbl(recipe.collectionTier)) do table.insert(gateIds,id) end
	table.sort(gateIds)
	for _,id in ipairs(gateIds) do
		local tierNeed=num(recipe.collectionTier[id],1)
		local _,tier=collectionInfo(id)
		local gateOk=tier>=tierNeed
		table.insert(gates,(gateOk and check or cross).." "..escape(itemName(id)).." collection "..numeral(tierNeed))
		if not gateOk then ok=false;reason=reason or ("Unlocks at "..itemName(id).." collection tier "..numeral(tierNeed)..".") end
	end
	local costIds={}
	for id in pairs(tbl(recipe.costs)) do table.insert(costIds,id) end
	table.sort(costIds,function(a,b) return itemName(a)<itemName(b) end)
	local ingredients={}
	for _,id in ipairs(costIds) do
		local needAmount=num(recipe.costs[id],0)
		local have=count("items",id)
		if have<needAmount then ok=false;reason=reason or ("Needs "..needAmount.." "..itemName(id)..".") end
		table.insert(ingredients,paint(fmt(have).."/"..fmt(needAmount),have>=needAmount and "9EE7D2" or "E8806A").." "..paint(escape(itemName(id)),itemHex(id)))
	end
	local out=itemDef(recipe.output)
	local owned=not recipe.repeatable and out~=nil and out.kind~="material" and out.kind~="consumable" and count("items",recipe.output)>0
	if owned then ok=false;reason=reason or ("You already own "..itemName(recipe.output)..".") end
	return ok,reason,gates,ingredients,owned
end
local function stationRecipes(station)
	local byCategory,categories={},{}
	for _,recipe in pairs(tbl(Data and Data.Recipes)) do
		if type(recipe)=="table" and recipe.station==station then
			local category=recipe.category or "Patterns"
			if not byCategory[category] then byCategory[category]={};table.insert(categories,category) end
			table.insert(byCategory[category],recipe)
		end
	end
	table.sort(categories,function(a,b)
		local ia,ib=table.find(categoryOrder,a) or 99,table.find(categoryOrder,b) or 99
		if ia~=ib then return ia<ib end
		return a<b
	end)
	for _,list in pairs(byCategory) do
		table.sort(list,function(a,b)
			if num(a.level,1)~=num(b.level,1) then return num(a.level,1)<num(b.level,1) end
			return itemName(a.output)<itemName(b.output)
		end)
	end
	return categories,byCategory
end
local function outputSummary(def)
	if not def then return "" end
	local parts={}
	if def.stats then table.insert(parts,statText(def.stats)) end
	if def.heal then table.insert(parts,"Restores "..paint(fmt(def.heal).." ❤","FF6B6B")) end
	if type(def.buff)=="table" then table.insert(parts,statText(def.buff.stats).." for "..clock(def.buff.duration)) end
	if def.kind=="accessory" then table.insert(parts,paint("✧ "..tostring(tbl(tbl(Data.Rarity)[def.rarity]).power or "?").." Magical Power","FFAA00")) end
	return table.concat(parts,"  ·  ")
end
local function drawForge()
	heading("GUILD    /    FORGE PATTERNS")
	for _, recipe in ipairs(tbl(state.recipes)) do
		if type(recipe)=="table" then
			local name=tostring(recipe.id)
			local ingredients={}
			local materials={}
			for material in pairs(tbl(recipe.costs)) do table.insert(materials,material) end
			table.sort(materials)
			for _,material in ipairs(materials) do table.insert(ingredients,recipe.costs[material] .. " " .. material .. " (" .. count("items",material) .. " held)") end
			local requirements={tostring(recipe.skill) .. " " .. tostring(recipe.level)}
			local gates={}
			for material in pairs(tbl(recipe.collection)) do table.insert(gates,material) end
			table.sort(gates)
			for _,material in ipairs(gates) do table.insert(requirements,recipe.collection[material] .. " lifetime " .. material) end
			local detail=tostring(recipe.description or name) .. ". " .. table.concat(ingredients, " + ") .. ". Requires " .. table.concat(requirements,", ") .. ". +" .. tostring(recipe.xp or 0) .. " " .. tostring(recipe.skill) .. " XP."
			local owned=not recipe.repeatable and count("items",name)>0
			row(name,detail,if owned then nil else (recipe.unlocked and "Craft" or "Locked"),function()
				if recipe.unlocked then send("craft",name) else notify("Requires " .. table.concat(requirements,", ") .. ".") end
			end)
		end
	end
	local rank = num(state.enchantRank,0)
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
local function drawStation(station)
	local categories,byCategory={}, {}
	if Data then categories,byCategory=stationRecipes(station) end
	if station=="Forge" and type(state.recipes)=="table" and #state.recipes>0 then table.insert(categories,"Guild") end
	if #categories==0 then
		if not Data then dataMissing() else card({motif="Workshop",title=station,detail="No patterns are recorded for this station yet."}) end
		return
	end
	local category=stationCategory[station]
	if not table.find(categories,category) then category=categories[1] end
	stationCategory[station]=category
	local levels=skillsOf(state)
	local skill=stationSkills[station]
	local info=skill and levels[skill]
	card({name="Station"..station,motif="Workshop",title=station,titleColor=gold,subtitle=(skill and info) and (skill.." "..info.level.." / "..maxLevel()) or nil,
		detail=stationNotes[station],bar=info and {fraction=info.fraction,color=rgb(skillHex(skill)),caption=info.maxed and "MAX LEVEL" or (fmt(math.max(0,info.ceiling-info.xp)).." XP to "..skill.." "..(info.level+1))} or nil,
		actions={{caption=craftableOnly and "Show all" or "Ready only",fn=function() craftableOnly=not craftableOnly;render() end}}})
	if #categories>1 then
		sectionBar(categories,category,function(name) stationCategory[station]=name;scroll.CanvasPosition=Vector2.zero;render() end,{small=true,prefix="Category"})
	end
	if category=="Guild" then drawForge() return end
	local shown=0
	for _,recipe in ipairs(byCategory[category] or {}) do
		local ok,reason,gates,ingredients,owned=recipeStatus(recipe,levels)
		if not craftableOnly or ok then
			shown+=1
			local out=itemDef(recipe.output)
			local amount=num(recipe.amount,1)
			local lines={table.concat(gates,"   "),"Needs "..table.concat(ingredients,"  ·  ")}
			local summary=outputSummary(out)
			if summary~="" then table.insert(lines,summary) end
			table.insert(lines,paint("+"..fmt(recipe.xp).." "..escape(tostring(recipe.skill)).." XP","F9CC77")..(recipe.repeatable and "  ·  repeatable" or ""))
			card({name="Recipe"..tostring(recipe.id),item=recipe.output,title=escape(out and out.name or recipe.output)..(amount>1 and ("  ×"..amount) or ""),titleColor=rgb(itemHex(recipe.output)),
				subtitle=escape((out and out.rarity or "").." "..kindLabel(out)).."  ·  Lv "..num(recipe.level,1),
				badge=owned and "OWNED" or (ok and "READY" or nil),badgeColor=owned and muted or mint,lines=lines,
				actions=not owned and {{caption="Craft",primary=ok,disabled=not ok,reason=reason,fn=function() send("craft",recipe.id) end}} or nil})
		end
	end
	if shown==0 then card({motif="Workshop",title="Nothing ready yet",detail="Gather the listed materials or level up to unlock more patterns.",actions={{caption="Show all",fn=function() craftableOnly=false;render() end}}}) end
end
local function drawWorkers()
	heading("ISLAND INDUSTRY")
	row("Worker fleet", "Up to three workers gather independently, including while away. Changing assignments collects completed output and restarts the current cycle.")
	local workers = tbl(state.workers)
	for slot = 1, 3 do
		local worker = workers[slot]
		if type(worker)=="table" then
			local slotId = tostring(slot)
			row("Worker " .. slot .. " · " .. tostring(worker.resource) .. " · Tier " .. tostring(worker.tier),
				tostring(worker.ready) .. " ready at last check. One resource every " .. tostring(worker.interval) .. " seconds; stores " .. tostring(worker.capacity) .. ".",
				"Collect", function() send("workerClaim", slotId) end)
			if num(worker.tier,3) < 3 then
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
	heading("HOME IMPROVEMENTS")
	for _, plan in ipairs({
		{ "Lanterns", "5 timber" },
		{ "Garden", "3 herb + 3 timber" },
		{
			"Deck",
			"10 timber + 5 ore",
		},
	}) do
		local name = plan[1]
		local built = type(state.decorations)=="table" and state.decorations[name]
		row(name, built and "Built on your home island" or plan[2], if built then nil else "Build", function()
			send("decorate", name)
		end)
	end
	local bond = num(state.companionBond,0)
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

Pages.drawStation,Pages.drawWorkers,Pages.drawHome=drawStation,drawWorkers,drawHome
end

------------------------------------------------------------------------------
-- Hunt: slayer lines and bestiary
------------------------------------------------------------------------------
do
local slayerTier={}
local function slayerMonsters(line)
	local list={}
	for _,monster in pairs(tbl(Data and Data.Monsters)) do if type(monster)=="table" and monster.slayer==line then table.insert(list,monster) end end
	table.sort(list,function(a,b) return num(a.level,0)<num(b.level,0) end)
	return list
end
local function slayerLevel(xp)
	local level=0
	for i,need in ipairs(tbl(Data and Data.SlayerLevels)) do if xp>=need then level=i else break end end
	return level
end
local function dropText(drops)
	local parts={}
	for _,drop in ipairs(tbl(drops)) do
		if type(drop)=="table" then
			local amount=drop.min==drop.max and tostring(drop.min) or (tostring(drop.min).."–"..tostring(drop.max))
			table.insert(parts,paint(escape(itemName(drop.item)),itemHex(drop.item)).." "..amount.." ("..chance(drop.chance)..")")
		end
	end
	return table.concat(parts,", ")
end
local function regionName(id)
	local region=Data and type(Data.RegionById)=="table" and Data.RegionById[id]
	return type(region)=="table" and region.name or tostring(id or "the wilds")
end
local function drawWardenHunts()
	if type(state.slayer)~="table" then return end
	local hunt = state.slayer
	heading("WARDEN    /    HUNT CONTRACTS")
	local reward = tostring(hunt.coins) .. " coins + " .. tostring(hunt.xp) .. " Combat XP."
	if hunt.active then
		row("Tier " .. tostring(hunt.tier) .. " hunt · " .. tostring(hunt.progress) .. " / " .. tostring(hunt.target),
			hunt.ready and ("Hunt complete. " .. reward) or ("Defeat Wardens after accepting this hunt. " .. reward),
			if hunt.ready then "Claim" else nil, function() send("slayerClaim") end)
	else
		row("Tier " .. tostring(hunt.tier) .. " Warden hunt", "Defeat " .. tostring(hunt.target) .. " Wardens. " .. reward .. " Higher tiers require longer hunts; tier 3 is repeatable.",
			"Accept", function() send("slayerStart") end)
	end
end
local function drawSlayer()
	if not Data or type(Data.Slayers)~="table" then dataMissing() drawWardenHunts() return end
	local d=depth()
	if not d then syncing("slayer contracts") drawWardenHunts() return end
	local slayer=tbl(d.slayer)
	local quest=type(slayer.quest)=="table" and slayer.quest or nil
	local levels=skillsOf(state)
	local combat=levels.Combat and levels.Combat.level or 1
	if quest then
		local def=tbl(Data.Slayers[quest.line])
		local tierIndex=num(quest.tier,1)
		local tierDef=tbl(tbl(def.tiers)[tierIndex])
		local progressValue,needed=num(quest.progress,0),num(quest.needed,num(tierDef.spawnXp,1))
		local ready=quest.bossReady==true
		local targets={}
		for _,monster in ipairs(slayerMonsters(quest.line)) do table.insert(targets,escape(monster.name).." ("..escape(regionName(monster.region))..")") end
		heading("ACTIVE CONTRACT")
		if ready then
			card({name="BossReady",motif="Hunt",fill=rgb("2A1A14"),edge=gold,accent=gold,title="BOSS READY",titleColor=gold,
				subtitle=escape(def.name or quest.line).." has emerged",
				detail="Return to its hunting grounds and defeat it: "..paint(fmt(tierDef.hp).." ❤","FF6B6B").."  ·  "..paint(fmt(tierDef.damage).." damage per hit","E8806A")..".",
				lines={"Reward: "..fmt(tierDef.xp).." slayer XP  ·  "..dropText(tierDef.drops)}})
		end
		card({name="SlayerQuest",motif="Hunt",accent=safeColor(def.color,ember),title=escape(def.name or quest.line).."  ·  Tier "..numeral(tierIndex),titleColor=rgb(lighten(type(def.color)=="string" and def.color or "C8553D",.35)),
			subtitle=escape(tostring(def.line or "")).." line",badge=ready and "READY" or (math.floor(math.clamp(progressValue/math.max(1,needed),0,1)*100).."%"),badgeColor=ready and gold or mint,
			detail=ready and "Slay the boss to complete the contract." or ("Slay "..table.concat(targets,", ").." to draw out the boss."),
			bar={fraction=ready and 1 or progressValue/math.max(1,needed),color=ready and gold or safeColor(def.color,ember),caption=fmt(progressValue).." / "..fmt(needed).." slayer progress"},
			actions={abandonConfirm and {caption="Confirm",fn=function() abandonConfirm=false;send("slayerAbandon") end} or {caption="Abandon",fn=function() abandonConfirm=true;render() end},
				abandonConfirm and {caption="Cancel",fn=function() abandonConfirm=false;render() end} or nil}})
		if abandonConfirm then para(container(),paint("Abandoning forfeits the contract fee. Confirm to give up this hunt.","E8806A"),1,muted) end
	end
	heading("SLAYER LINES")
	for _,line in ipairs(tbl(Data.SlayerOrder)) do
		local def=Data.Slayers[line]
		if type(def)=="table" then
			local info=tbl(tbl(slayer.lines)[line])
			local xp=num(info.xp,0)
			local level=num(info.level,nil) or slayerLevel(xp)
			local thresholds=tbl(Data.SlayerLevels)
			local nextAt=num(info.nextAt,nil) or thresholds[level+1]
			local previous=thresholds[level] or 0
			local hex=type(def.color)=="string" and def.color or "C8553D"
			local targets={}
			for _,monster in ipairs(slayerMonsters(line)) do table.insert(targets,escape(monster.name)) end
			local lineCombat=num(tbl(def.requires).Combat,1)
			card({name="Slayer"..line,motif="Hunt",accent=rgb(hex),title=escape(def.name or line),titleColor=rgb(lighten(hex,.4)),
				subtitle=escape(tostring(def.line or "")).." line  ·  Slayer "..level.." / "..#thresholds,badge=(combat>=lineCombat and check or cross).." Combat "..lineCombat,badgeColor=ivory,
				detail="Per level: "..statText(def.rewardStat)..(#targets>0 and ("  ·  Targets: "..table.concat(targets,", ")) or ""),
				bar={fraction=nextAt and math.clamp((xp-previous)/math.max(1,nextAt-previous),0,1) or 1,color=rgb(hex),caption=nextAt and (fmt(xp).." / "..fmt(nextAt).." slayer XP") or "MAX SLAYER LEVEL"}})
			local tiers=tbl(def.tiers)
			if #tiers>0 then
				local selected=math.clamp(num(slayerTier[line],1),1,#tiers)
				local names={}
				for i=1,#tiers do names[i]="Tier "..numeral(i) end
				sectionBar(names,"Tier "..numeral(selected),function(name)
					slayerTier[line]=table.find(names,name) or 1
					render()
				end,{small=true,prefix=line,maxPer=4})
				local tierDef=tbl(tiers[selected])
				local cost=num(tierDef.cost,0)
				local needCombat=math.max(lineCombat,num(tierDef.combatLevel,1))
				local coinsOk=num(state.coins,0)>=cost
				local combatOk=combat>=needCombat
				local reason=quest and "Finish or abandon your active contract first." or (not combatOk and ("Requires Combat "..needCombat..".")) or (not coinsOk and ("Needs "..fmt(cost).." coins.")) or nil
				card({name="SlayerTier"..line,motif="Hunt",title=escape(def.name or line).."  ·  Tier "..numeral(selected),titleColor=ivory,
					subtitle=paint(fmt(tierDef.hp).." ❤","FF6B6B").."  ·  "..paint(fmt(tierDef.damage).." damage","E8806A"),
					badge=paint(fmt(cost).." coins",coinsOk and "F9CC77" or "E8806A"),
					lines={(combatOk and check or cross).." Combat "..needCombat.."   "..(coinsOk and check or cross).." "..fmt(cost).." coins",
						"Summon after "..fmt(tierDef.spawnXp).." slayer progress  ·  Reward "..fmt(tierDef.xp).." slayer XP",
						"Drops: "..dropText(tierDef.drops)},
					actions={{caption="Begin",primary=reason==nil,disabled=reason~=nil,reason=reason,fn=function() send("slayerBegin",line..":"..selected) end}}})
			end
		end
	end
	drawWardenHunts()
end
local function drawBestiary()
	if not Data or type(Data.Monsters)~="table" then dataMissing() return end
	local d=depth()
	if not d then syncing("bestiary") return end
	local kills=tbl(d.bestiary)
	local milestones=tbl(Data.BestiaryTiers)
	local totalTiers=0
	for id,n in pairs(kills) do
		if Data.Monsters[id] then for _,need in ipairs(milestones) do if num(n,0)>=need then totalTiers+=1 end end end
	end
	totalTiers=num(tbl(d.stats).bestiaryTiers,totalTiers)
	card({name="BestiarySummary",motif="Hunt",title="Bestiary",titleColor=gold,subtitle=totalTiers.." milestones reached",
		detail="Each milestone on any creature grants "..statText(Data.BestiaryBonus).." permanently.",
		lines={totalTiers>0 and ("Earned: "..statText(Data.BestiaryBonus,totalTiers)) or nil}})
	local labels={}
	for i,need in ipairs(milestones) do labels[i]=short(need) end
	local placed={}
	local groups={}
	for _,region in ipairs(tbl(Data.Regions)) do
		local list={}
		for _,id in ipairs(tbl(region.monsters)) do if Data.Monsters[id] and not placed[id] then placed[id]=true;table.insert(list,id) end end
		if #list>0 then table.insert(groups,{name=region.name,list=list}) end
	end
	local rest={}
	for id in pairs(Data.Monsters) do if not placed[id] then table.insert(rest,id) end end
	table.sort(rest)
	if #rest>0 then table.insert(groups,{name="Elsewhere",list=rest}) end
	-- Sea creatures: hooked while fishing (Data.SeaCreatures, resolved through Data.Monsters).
	local sea={}
	for _,id in ipairs(tbl(Data.SeaCreatureOrder)) do if type(Data.Monsters[id])=="table" then table.insert(sea,id) end end
	if #sea>0 then table.insert(groups,{name="Sea creatures",list=sea}) end
	for _,group in ipairs(groups) do
		heading(string.upper(tostring(group.name)))
		table.sort(group.list,function(a,b) return num(Data.Monsters[a].level,0)<num(Data.Monsters[b].level,0) end)
		for _,id in ipairs(group.list) do
			local monster=Data.Monsters[id]
			local n=num(kills[id],0)
			if n<=0 then
				card({name="Beast"..id,locked=true,title="???",titleColor=muted,subtitle="Lv "..num(monster.level,1).."  ·  not yet encountered",
					detail=monster.seaCreature and ("Hooked while fishing at Fishing "..num(monster.fishing,1)..".") or "Defeat this creature to record it."})
			else
				local tier=0
				for i,need in ipairs(milestones) do if n>=need then tier=i end end
				local nextNeed=milestones[tier+1]
				local previous=milestones[tier] or 0
				local hex=type(monster.color)=="string" and monster.color or "C8553D"
				card({name="Beast"..id,icon=function(parent,size) return itemGlyph(parent,{name=monster.name,color=hex},size) end,
					title=escape(monster.name),titleColor=rgb(lighten(hex,.35)),subtitle="Lv "..num(monster.level,1).."  ·  "..paint(fmt(monster.hp).." ❤","FF6B6B").."  ·  "..fmt(monster.xp).." Combat XP",
					badge=fmt(n).." kills",badgeColor=ivory,pips={total=#milestones,filled=tier,color=rgb(hex),labels=labels},
					bar={fraction=nextNeed and math.clamp((n-previous)/math.max(1,nextNeed-previous),0,1) or 1,color=gold,caption=nextNeed and (fmt(n).." / "..fmt(nextNeed).." to milestone "..numeral(tier+1)) or "BESTIARY COMPLETE"},
					lines={"Drops: "..dropText(monster.drops)..(monster.slayer and ("  ·  "..paint(escape(tostring(monster.slayer)).." slayer target","E8806A")) or ""),
						monster.seaCreature and paint("Fishing "..num(monster.fishing,1).."  ·  +"..fmt(num(monster.fishingXp,0)).." Fishing XP  ·  "..(monster.waters and escape(table.concat(monster.waters,", ")).." waters" or "any water"),"9EE7D2") or nil}})
			end
		end
	end
end

Pages.drawSlayer,Pages.drawBestiary=drawSlayer,drawBestiary
end

------------------------------------------------------------------------------
-- Hunt › Dungeon: Observatory floors, grading and credit rules (Dungeons team).
-- Read-only: floors are chosen at the in-world daises by the Vault Gate.
------------------------------------------------------------------------------
do
local dungeonUi={violet="8E7CC3"}
function dungeonUi.drops(list)
	local parts={}
	for _,drop in ipairs(tbl(list)) do
		if type(drop)=="table" then table.insert(parts,paint(escape(itemName(drop.item)),itemHex(drop.item)).." ("..chance(drop.chance)..")") end
	end
	return table.concat(parts,", ")
end
function dungeonUi.mechanics(m)
	m=tbl(m)
	local out={}
	if m.orderedPrisms then table.insert(out,"Tune prisms in the order shown") end
	if type(m.shieldPhases)=="table" then table.insert(out,"Core shields at "..#m.shieldPhases.." HP thresholds; retune to break") end
	if type(m.addWaves)=="table" then table.insert(out,num(m.addWaves.count,0).." umbral wisps every "..num(m.addWaves.every,0).."s ward the boss") end
	if type(m.enrage)=="table" then table.insert(out,"Enrages after "..num(m.enrage.after,0).."s ("..num(m.enrage.damageMult,1).."× damage)") end
	return #out>0 and table.concat(out,"  ·  ") or "The original three-prism encounter"
end
local function drawDungeon()
	if not Data or type(Data.DungeonFloors)~="table" or type(Data.Dungeons)~="table" then dataMissing() return end
	local levels=skillsOf(state)
	local level=levels.Dungeoneering and levels.Dungeoneering.level or 1
	local rules=Data.Dungeons
	local result=player:GetAttribute("DungeonResult")
	local notice=player:GetAttribute("ExpeditionNotice")
	local chosen=num(player:GetAttribute("ExpeditionFloor"),1)
	card({name="DungeonSummary",motif="Hunt",accent=rgb(dungeonUi.violet),title="The Hollow Observatory",titleColor=rgb(lighten(dungeonUi.violet,.35)),
		subtitle="Dungeoneering "..level.."  ·  Selected: Floor "..numeral(chosen),badge="Party ≤ "..num(rules.maxParty,5),badgeColor=ivory,
		detail="Choose a floor at the daises beside the Vault Gate, open the run at the gate, then stand on the matchmaking pad within "..num(rules.padSeconds,10).."s to join.",
		lines={type(result)=="string" and result~="" and ("Last clear: "..escape(result)) or nil,
			type(notice)=="string" and notice~="" and paint(escape(notice),"F9CC77") or nil}})
	heading("FLOORS")
	for index,f in ipairs(Data.DungeonFloors) do
		if type(f)=="table" then
			local need=num(f.level,1)
			local open=level>=need
			local boss=tbl(f.boss)
			local rw=tbl(f.rewards)
			card({name="DungeonFloor"..index,motif="Hunt",locked=not open,accent=open and rgb(dungeonUi.violet) or nil,
				title=escape(f.name or ("Floor "..index)).."  ·  "..escape(f.subtitle or ""),titleColor=open and ivory or muted,
				subtitle="Boss: "..escape(boss.name or "?").."  ·  "..paint(escape(boss.attack or ""),"E8806A"),
				badge=(open and check or cross).." Dungeoneering "..need,badgeColor=ivory,
				detail=dungeonUi.mechanics(f.mechanics),
				lines={"Grade B reward: "..fmt(rw.dungeoneeringXp).." Dungeoneering XP  ·  "..fmt(rw.combatXp).." Combat XP  ·  "..fmt(rw.coins).." coins  ·  "..num(rw.stormglass,0).." Stormglass",
					"Chest: "..dungeonUi.drops(f.chest)}})
		end
	end
	heading("SCORE & GRADE")
	local grades={}
	for _,g in ipairs(tbl(Data.DungeonGrades)) do
		if type(g)=="table" then table.insert(grades,paint(escape(g.grade),"F9CC77").." ≥"..num(g.min,0).." ×"..num(g.mult,1)) end
	end
	card({name="DungeonGrades",motif="Hunt",title="Score = speed + survival + puzzle",titleColor=gold,subtitle="Each part 0–100 · total 300",
		detail="Speed is full until the floor's par time and reaches 0 at twice par. Each death costs 20 survival; each wrong prism costs 15 puzzle.",
		lines={table.concat(grades,"   "),"Higher grades multiply XP, coins and essence, add Stormglass at S/S+, and boost the chest's rare roll (Magic Find applies too)."}})
	card({name="DungeonRules",motif="Hunt",title="Fair credit",titleColor=ivory,
		lines={"Contribute at least "..math.floor(num(rules.contributionShare,0.1)*100).."% of the party's damage and tuning to open the chest.",
			"Chest cooldown: "..num(rules.clearCooldown,90).."s between credited clears.",
			"Ironman journals are credited on solo clears or with "..math.floor(num(rules.ironmanDamageShare,0.3)*100).."% of the party's damage."}})
end
Pages.drawDungeon=drawDungeon
end

------------------------------------------------------------------------------
-- Ledger: bank, market, merchant
------------------------------------------------------------------------------
do
local bankDirection="deposit"
local bankAmount="all"
local function drawBank()
	heading("01    /    BANK LEDGER")
	local balance=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,88),deep))
	rounded(balance,10,gold)
	local crest=motif(balance,"Ledger",42)
	crest.Position=UDim2.fromOffset(10,12)
	label(balance,"WAYFARER VAULT",64,8,UDim.new(1,-76),18,bold,10,gold)
	label(balance,"Purse  "..fmt(num(state.coins,0)).."     /     Vault  "..fmt(num(state.bank,0)),64,29,UDim.new(1,-76),23,bold,compactAtlas and 13 or 16,ivory)
	label(balance,"Stored coins are protected from death loss.",12,61,UDim.new(1,-24),19,regular,11,muted)
	local direction=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,44),ink))
	for index,option in ipairs({{"deposit","Deposit"},{"withdraw","Withdraw"}}) do
		local selected=option[1]
		local control=button(direction,option[2],UDim2.new((index-1)*.5,0,0,0),UDim2.new(.5,-4,0,44),function() bankDirection=selected;render() end)
		control.BackgroundColor3=bankDirection==selected and mint or slate
		control.TextColor3=bankDirection==selected and deep or ivory
	end
	local entry=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,44),deep))
	rounded(entry,8,slate)
	label(entry,"AMOUNT",10,0,UDim.new(0,72),44,bold,11,mint)
	local input=make("TextBox",entry,{Name="BankAmount",Position=UDim2.fromOffset(87,0),Size=UDim2.new(1,-97,0,44),BackgroundTransparency=1,Text=bankAmount,PlaceholderText="Whole coins, half or all",PlaceholderColor3=muted,TextColor3=ivory,TextSize=16,Font=bold,ClearTextOnFocus=false,TextXAlignment=Enum.TextXAlignment.Left,Selectable=true,MultiLine=false})
	local presets=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,44),ink))
	local preview=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,54),deep))
	rounded(preview,8,slate)
	local projected=label(preview,"",10,5,UDim.new(1,-20),44,regular,compactAtlas and 12 or 13,muted)
	projected.TextWrapped=true
	projected.TextTruncate=Enum.TextTruncate.None
	local transferRow=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,44),ink))
	local transfer
	local function requested()
		local raw=bankAmount:lower():match("^%s*(.-)%s*$")
		local available=bankDirection=="deposit" and num(state.coins,0) or num(state.bank,0)
		local amount
		if raw=="all" then amount=available elseif raw=="half" then amount=math.floor(available/2) elseif raw:match("^%d+$") and #raw<=10 then amount=tonumber(raw) end
		if available==0 then return nil,raw,"No coins available in your "..(bankDirection=="deposit" and "purse." or "vault.") end
		if not amount or amount<1 or ((raw~="all" and raw~="half") and amount>1000000000) or amount%1~=0 then return nil,raw,"Enter 1–1,000,000,000 whole coins, half or all." end
		if amount>available then return nil,raw,"Amount exceeds the "..(bankDirection=="deposit" and "purse" or "vault").." balance." end
		return amount,raw
	end
	local function updatePreview()
		local amount,_,problem=requested()
		if amount then
			local purseAfter=num(state.coins,0)+(bankDirection=="deposit" and -amount or amount)
			local vault=num(state.bank,0)+(bankDirection=="deposit" and amount or -amount)
			projected.Text="After transfer: Purse "..fmt(purseAfter).."  /  Vault "..fmt(vault)..". Your balance is checked again when you transfer."
			projected.TextColor3=mint
			transfer.Text=(bankDirection=="deposit" and "Deposit " or "Withdraw ")..fmt(amount).." coins"
		else
			projected.Text=problem
			projected.TextColor3=gold
			transfer.Text=bankDirection=="deposit" and "Deposit coins" or "Withdraw coins"
		end
	end
	transfer=button(transferRow,"Transfer",UDim2.new(),UDim2.new(1,0,0,44),function()
		local amount,raw,problem=requested()
		if not amount then notify(problem);return end
		send(bankDirection,raw..":"..tostring(state.bankRevision or 0))
	end)
	for index,preset in ipairs({"25","100","half","all"}) do
		button(presets,preset=="half" and "Half" or (preset=="all" and "All" or preset),UDim2.new((index-1)/4,0,0,0),UDim2.new(.25,-4,0,44),function()
			bankAmount=preset
			input.Text=preset
			updatePreview()
		end)
	end
	input.SelectionGained:Connect(function() revealSelection(input) end)
	input:GetPropertyChangedSignal("Text"):Connect(function()
		bankAmount=input.Text:sub(1,20)
		updatePreview()
	end)
	input.FocusLost:Connect(function() updatePreview() end)
	updatePreview()
end
local buyLimits,listPrices={},{}
local function quoteAge(quote)
	return math.max(0,math.floor(workspace:GetServerTimeNow()-(quote.fetchedAt or 0)))
end
local function validPrice(value,quote)
	if not value or not value:match("^%d+$") or #value>5 then return nil end
	local price=tonumber(value)
	if not price or price<(quote.minPrice or 1) or price>(quote.maxPrice or 10000) then return nil end
	return price
end
local function priceField(title,value,onChange)
	local field=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,70),deep))
	rounded(field,8,slate)
	label(field,title,10,3,UDim.new(1,-20),20,bold,11,mint)
	local box=make("TextBox",field,{Name=title:gsub("[^%w]","").."Input",Position=UDim2.fromOffset(10,24),Size=UDim2.new(1,-20,0,44),BackgroundTransparency=1,Text=value,PlaceholderText="1–10,000 whole coins per lot",PlaceholderColor3=muted,TextColor3=ivory,TextSize=16,Font=bold,ClearTextOnFocus=false,Selectable=true,TextXAlignment=Enum.TextXAlignment.Left,MultiLine=false})
	box.SelectionGained:Connect(function() revealSelection(box) end)
	box:GetPropertyChangedSignal("Text"):Connect(function() onChange(box.Text:sub(1,20)) end)
	return box
end
local function drawMarket()
	heading("MARKET    /    PLAYER ASK BOARD")
	if state.ironman then row("Sealed charter","Player trading is unavailable in Ironman.");return end
	local chooser=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,44),ink))
	for index,item in ipairs({"Ore","Timber","Herb","Fish"}) do
		local choice=button(chooser,item,UDim2.new((index-1)/4,0,0,0),UDim2.new(.25,-4,0,44),function()
			marketItem=item
			purchaseReview=nil
			scroll.CanvasPosition=Vector2.zero
			render()
			send("market",item)
		end)
		choice.BackgroundColor3=item==marketItem and mint or slate
		choice.TextColor3=item==marketItem and deep or ivory
	end
	local item=marketItem
	local quote=marketQuotes[item]
	if not quote then
		row(item.." order board","Read current player asking prices before choosing a trade.","Refresh",function() send("market",item) end)
		return
	end
	local units=quote.lotSize or 3
	local age=quoteAge(quote)
	local best=quote.bestAsk and (quote.bestAsk.." coins / "..units.." "..item) or "No other player asks"
	row(item.." · best ask",best..". "..tostring(quote.openLots).." open lots; "..tostring(quote.ownLots).." are yours. Quote checked "..age.." seconds ago. Prices may change before a trade.","Refresh",function() send("market",item) end)
	if marketChanges[item] then row("Best price updated",marketChanges[item].." Your purchase limit stays unchanged.") end
	if age>=15 then row("Quote may be stale","Refresh for a current best ask. The server still enforces your maximum total price.") end
	if not buyLimits[item] then buyLimits[item]=tostring(quote.bestAsk or quote.defaultPrice) end
	if not listPrices[item] then listPrices[item]=tostring(quote.defaultPrice) end
	heading("BUY    /    PRICE-PROTECTED LOT")
	if purchaseReview and purchaseReview.item==item then
		local review=purchaseReview
		local latest=quote.bestAsk and ("Latest best ask: "..quote.bestAsk.." coins.") or "There is no eligible ask in this quote."
		row("Review "..units.." "..item,"Maximum total: "..review.limit.." coins for one "..units.."-unit lot. "..latest.." The cheapest eligible lot at or below your limit fills; any difference is returned. If no lot meets your limit, the reservation is returned.","Confirm",function()
			purchaseReview=nil
			send("buy",item..":"..review.limit)
		end)
		row("Keep deciding","Cancel this review without placing a purchase.","Cancel",function() purchaseReview=nil;render() end)
	else
		local box=priceField("MAXIMUM TOTAL / "..units.." "..item,buyLimits[item],function(value) buyLimits[item]=value end)
		local presets=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,44),ink))
		button(presets,"Use best ask",UDim2.new(),UDim2.new(.5,-4,0,44),function()
			if quote.bestAsk then buyLimits[item]=tostring(quote.bestAsk);box.Text=buyLimits[item] else notify("No eligible ask in this quote. Refresh to check again.") end
		end)
		button(presets,"Review buy",UDim2.new(.5,0,0,0),UDim2.new(.5,-4,0,44),function()
			local limit=validPrice(buyLimits[item],quote)
			if not limit then notify("Choose a maximum total of 1–10,000 whole coins.");return end
			if num(state.coins,0)<limit then notify("Your purse needs "..limit.." coins to reserve this purchase.");return end
			purchaseReview={item=item,limit=limit,revision=quote.revision}
			render()
		end)
	end
	heading("SELL    /    YOUR ASKING PRICE")
	priceField("ASK TOTAL / "..units.." "..item,listPrices[item],function(value) listPrices[item]=value end)
	row("List "..units.." "..item,"Choose the total price for one lot. Your materials are reserved until sold or cancelled. "..count("items",item).." held in your satchel.","List lot",function()
		local price=validPrice(listPrices[item],quote)
		if not price then notify("Choose an asking total of 1–10,000 whole coins.");return end
		send("list",item..":"..price)
	end)
	row("Your "..item.." orders",tostring(quote.ownLots).." open lots. Cancel returns your first fixed-price lot from the old market, or your oldest priced lot.","Cancel lot",function() send("cancel",item) end)
	row(item.." sale proceeds",tostring(quote.proceeds).." coins waiting in this commodity ledger.","Collect",function() send("proceeds",item) end)
	row("How matching works","Buy one lot at the lowest available ask from another player. At equal prices, listings from the old fixed-price market go first. Within each group, the oldest listing sells first.")
end
local function drawMerchant()
	heading("MERCHANT    /    IMMEDIATE SALES")
	row("Sell raw materials","Sell all eligible materials in your satchel to the merchant.","Sell all",function() send("sell") end)
	card({motif="Satchel",title="Sell anything",detail="Open Satchel → Items and tap any item to sell that stack at its merchant value.",
		actions={{caption="Open Satchel",fn=function() current="Satchel";sectionOf.Satchel="Items";scroll.CanvasPosition=Vector2.zero;render() end}}})
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
	-- coopConfirm holds the one pending confirmation: "create", a group id,
	-- "leave", "kick:<id>" or "transfer:<id>" (keeps top-level locals flat).
	local function confirmRow(key, title, detail, ask, fn)
		local confirming = coopConfirm == key
		row(title, confirming and ask or detail, confirming and "Confirm" or "Review", function()
			if coopConfirm == key then coopConfirm=nil; fn() else coopConfirm=key; render() end
		end)
	end
	if group.preview then row("Studio practice", "This co-op ledger is temporary and will not save.") end
	if group.pendingGroup then
		row("Membership needs recovery", "Retry the membership you already chose. This completes the same crew membership.", "Retry", function()
			if group.pendingGroup == tostring(player.UserId) then sendCoop("create") else sendCoop("accept",group.pendingGroup) end
		end)
		return
	end
	if not group.groupId then
		if group.removal then row("Removed from your crew", "Reason: " .. tostring(group.removal.reason or "not given") .. ". Your own journal, satchel and island are unchanged.") end
		if group.cooldownUntil then
			row("Rejoin cooldown", "You can join or found a crew again in " .. tostring(group.cooldownText) .. ". The cooldown stops crew hopping.")
		end
		row("A shared crew", "Create or join a crew of up to four voyagers in the same mode. Leaving or being removed starts a 24 hour cooldown before any new crew. Your personal island and inventory stay separate.")
		if not group.cooldownUntil then
			confirmRow("create", "Found a shared homestead", "Start a crew, then invite players from this server.",
				"You become the crew leader. If you leave later, supplies you gave stay with the crew and a 24 hour cooldown starts.", function() sendCoop("create") end)
		end
		heading("INVITATIONS")
		if #(group.invites or {}) == 0 then row("No invitations", "Ask a crew leader in this server to invite you, then refresh.") end
		for _, invite in ipairs(group.invites or {}) do
			local groupId = invite.groupId
			confirmRow(groupId, "Join " .. invite.name .. "’s crew", (invite.ironman and "Group Ironman" or "Standard") .. " crew invitation. Review before joining.",
				"Supplies you give stay with this crew. Leaving or being removed starts a 24 hour cooldown. Confirm to join.", function() sendCoop("accept",groupId) end)
		end
	else
		local members = group.members or {}
		local isLeader = group.owner == player.UserId
		local level = group.level or {}
		row((group.ironman and "Group Ironman" or "Standard") .. " crew · " .. #members .. " / " .. tostring(group.maxMembers or 4),
			group.ironman and "Travel to your shared homestead from Compass Quay. Ironman crews trade only through their own shared stores." or "Travel to your shared homestead from Compass Quay.")
		heading("HOMESTEAD LEVEL")
		local width = (level.nextXp or level.xp or 0) - (level.floor or 0)
		local perkText, nextText = {}, {}
		for stat, value in pairs(level.stats or {}) do table.insert(perkText, "+" .. value .. " " .. stat) end
		for stat, value in pairs(level.nextStats or {}) do table.insert(nextText, "+" .. value .. " " .. stat) end
		table.sort(perkText)
		table.sort(nextText)
		card({title=escape("Homestead level " .. tostring(level.level or 1)), badge=tostring(level.xp or 0) .. " XP",
			detail=escape("Contributions raise the level: shared gathers, net-new deposits and shared construction."),
			lines={escape("Perks: " .. (#perkText > 0 and table.concat(perkText, ", ") or "none yet") .. " · storage " .. tostring(level.storage or 0) .. " each · " .. tostring(level.workerSlots or 0) .. " shared workers (tier " .. tostring(level.workerTier or 0) .. ")"),
				level.nextXp and escape("Next level at " .. level.nextXp .. " XP: " .. table.concat(nextText, ", ") .. ", storage " .. tostring(level.nextStorage) .. ", " .. tostring(level.nextWorkers) .. " workers") or "Highest homestead level reached."},
			bar={fraction=level.nextXp and width > 0 and ((level.xp or 0) - (level.floor or 0)) / width or 1, caption=level.nextXp and ((level.xp or 0) .. " / " .. level.nextXp) or "MAX"}})
		heading("CREW ROSTER")
		local memberIds = {}
		for _, member in ipairs(members) do
			memberIds[member.userId] = true
			local mine = member.userId == player.UserId
			local actions = {}
			if isLeader and not mine then
				table.insert(actions, {caption=coopConfirm == "transfer:" .. member.userId and "Confirm lead" or "Make leader", name="TransferButton", fn=function()
					local key = "transfer:" .. member.userId
					if coopConfirm == key then coopConfirm=nil; sendCoop("transfer", tostring(member.userId), "confirm") else coopConfirm=key; render() end
				end})
				table.insert(actions, {caption="Remove", name="KickButton", fn=function() coopConfirm="kick:" .. member.userId; render() end})
			elseif mine then
				table.insert(actions, {caption=coopConfirm == "leave" and "Confirm leave" or "Leave", name="LeaveButton", fn=function()
					if coopConfirm == "leave" then coopConfirm=nil; sendCoop("leave","confirm") else coopConfirm="leave"; render() end
				end})
			end
			card({title=escape(member.name), badge=member.role or "Member", subtitle=escape(tostring(member.points or 0) .. " contribution"),
				lines={escape("Gathered " .. tostring(member.gathered or 0) .. " · deposited " .. tostring(member.deposited or 0) .. " · withdrew " .. tostring(member.withdrawn or 0) .. " · built " .. tostring(member.built or 0) .. " · workers " .. tostring(member.worker or 0))},
				actions=#actions > 0 and actions or nil})
			if coopConfirm == "leave" and mine then
				row("Leave this crew?", (isLeader and #members > 1 and "Leadership passes to the longest-standing member. " or "") .. (#members == 1 and "You are the last member: the crew disbands. " or "") .. "Supplies you gave stay with the crew. A 24 hour cooldown starts before any new crew.")
			end
			if coopConfirm == "transfer:" .. member.userId then
				row("Pass leadership to " .. member.name .. "?", "They can invite, remove members and pass leadership on. You stay as a member.")
			end
			if coopConfirm == "kick:" .. member.userId then
				heading("REMOVE " .. string.upper(member.name) .. " · CHOOSE A REASON")
				for _, reason in ipairs(group.kickReasons or {}) do
					row(reason.text, "Removes " .. member.name .. " from the crew. Their own journal, satchel and island are untouched; they wait 24 hours before joining any crew.", "Remove", function()
						coopConfirm=nil; sendCoop("kick", tostring(member.userId), reason.id)
					end)
				end
			end
		end
		if isLeader and #members < (group.maxMembers or 4) then
			heading("INVITE FROM THIS SERVER")
			for _, invite in ipairs(group.outgoing or {}) do
				local userId = tostring(invite.userId)
				row("Invitation to " .. tostring(invite.name or ("Voyager " .. userId)), "Expires in " .. math.max(1, math.ceil((invite.expiresIn or 0) / 60)) .. " min unless accepted.", "Revoke", function() sendCoop("revoke", userId) end)
			end
			local candidates = 0
			for _, candidate in ipairs(Players:GetPlayers()) do
				if not memberIds[candidate.UserId] then
					candidates += 1
					local userId = tostring(candidate.UserId)
					row(candidate.DisplayName .. " (@" .. candidate.Name .. ")", "The server checks that this player has the same mode and no rejoin cooldown.", "Invite", function() sendCoop("invite",userId) end)
				end
			end
			if candidates == 0 then row("No other voyagers here", "Invite friends after they join this server.") end
		end
		heading("SHARED STORES")
		row("Crew stores", "Gather at shared-island prompts, deposit from your satchel or let shared workers fill these stores. Any member may withdraw. Supplies stay with the crew when someone leaves.")
		local resources = group.resources or {"Timber","Ore","Herb","Fish"}
		for _, resource in ipairs(resources) do
			local held = count("items", resource)
			card({title=escape(resource), badge=tostring((group.supplies or {})[resource] or 0) .. " / " .. tostring(level.storage or 0),
				subtitle=escape(tostring(held) .. " in your satchel"),
				actions={{caption="Deposit 10", name="Deposit" .. resource, disabled=held < 10, reason="You need 10 " .. resource .. " in your satchel.", fn=function() sendCoop("deposit", resource, "10") end},
					{caption="Withdraw 10", name="Withdraw" .. resource, fn=function() sendCoop("withdraw", resource, "10") end}}})
		end
		heading("SHARED WORKERS")
		if #(group.workers or {}) == 0 then row("No shared workers yet", "Reach homestead level 2 to unlock the first shared worker, and level 4 for the second.") end
		for _, w in ipairs(group.workers or {}) do
			local slot = tostring(w.slot)
			local actions = {}
			if w.resource then
				table.insert(actions, {caption="Collect", name="ClaimButton", fn=function() sendCoop("claim") end})
				if w.upgradeCost then table.insert(actions, {caption="Upgrade", name="UpgradeButton", fn=function() sendCoop("upgrade", slot) end}) end
			end
			local nextResource = resources[(table.find(resources, w.resource or "") or 0) % #resources + 1]
			table.insert(actions, {caption=(w.resource and "Set " or "Assign ") .. nextResource, name="AssignButton", fn=function() sendCoop("assign", slot, nextResource) end})
			local costText = w.upgradeCost and (" · upgrade " .. tostring(w.upgradeCost.Timber or 0) .. " timber + " .. tostring(w.upgradeCost.Ore or 0) .. " ore") or ""
			card({title=escape("Shared worker " .. slot), badge=w.resource and ("Tier " .. tostring(w.tier)) or "Idle",
				subtitle=escape(w.resource and (w.resource .. " every " .. tostring(w.interval) .. " s") or "Any member can assign it"),
				lines={w.resource and escape(tostring(w.ready) .. " / " .. tostring(w.capacity) .. " ready, collected once into the shared stores" .. costText) or ""},
				bar=w.resource and {fraction=(w.capacity or 0) > 0 and (w.ready or 0) / w.capacity or 0, caption=tostring(w.ready or 0) .. " / " .. tostring(w.capacity or 0)} or nil,
				actions=actions})
		end
		heading("SHARED IMPROVEMENTS")
		for _, plan in ipairs({{"Garden","3 herb + 3 timber"},{"Lanterns","5 timber"},{"Deck","10 timber + 5 ore"}}) do
			local name = plan[1]
			local built = (group.decorations or {})[name]
			row(name, built and "Built on the shared homestead" or (plan[2] .. " from shared stores"), if built then nil else "Build", function() sendCoop("build",name) end)
		end
		if #(group.log or {}) > 0 then
			heading("CREW LOG")
			local lines = {}
			for i, text in ipairs(group.log) do lines[i] = escape(tostring(text)) end
			card({title="Recent crew activity", lines=lines})
		end
	end
	if coopConfirm then row("Keep deciding", "Cancel this confirmation without changing your membership.", "Cancel", function() coopConfirm=nil; render() end) end
	row("Shared ledger", "Refresh after crew activity or to check new invitations.", "Refresh", function() sendCoop("state") end)
end

-- Economy: Bazaar standing orders (Orders) and the Auction House (Auctions).
-- All page state lives in one table (the chunk is at the local-register limit).
local U={group="Mining",item="Ore",qty="10",price="",cat="weapon",page=1,listItem=nil,listPrice="",confirm=nil}
function U.rules()
	local rules=Data and type(Data.Economy)=="table" and Data.Economy or nil
	return {orderCap=num(rules and rules.orderCap,10),listingCap=num(rules and rules.listingCap,10),maxQuantity=num(rules and rules.maxQuantity,640),
		maxPrice=num(rules and rules.maxPrice,1000000),feePercent=num(rules and rules.feePercent,1),
		categories=type(rules and rules.auctionCategories)=="table" and rules.auctionCategories or {"weapon","armor","tool","accessory","pet"},
		names=type(rules and rules.categoryNames)=="table" and rules.categoryNames or {weapon="Weapons",armor="Armor",tool="Tools",accessory="Accessories",pet="Pets"},
		groups=type(rules and rules.bazaarGroups)=="table" and rules.bazaarGroups or {"Mining","Woodcutting","Fishing","Farming","Materials"}}
end
function U.economy() return tbl(state.economy) end
function U.fee(price)
	local rules=Data and type(Data.Economy)=="table" and Data.Economy
	if rules and type(rules.auctionFee)=="function" then return rules.auctionFee(price) end
	return math.max(1,math.ceil(price/100))
end
function U.whole(value,low,high)
	if type(value)~="string" or not value:match("^%d+$") or #value>7 then return nil end
	local n=tonumber(value)
	if not n or n<low or n>high then return nil end
	return n
end
function U.commodities(group)
	local list={}
	for id,def in pairs(tbl(Data and Data.Items)) do
		if type(def)=="table" and (def.kind=="resource" or def.kind=="material") then
			local own=def.kind=="resource" and type(Data.ResourceSkill)=="table" and Data.ResourceSkill[id] or "Materials"
			if own==group then table.insert(list,id) end
		end
	end
	table.sort(list,function(a,b)
		local da,db=itemDef(a),itemDef(b)
		local ta,tb=num(da and da.tier,0),num(db and db.tier,0)
		if ta~=tb then return ta<tb end
		return tostring(da and da.name or a)<tostring(db and db.name or b)
	end)
	return list
end
function U.field(title,name,value,placeholder,onChange)
	local field=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,70),deep))
	rounded(field,8,slate)
	label(field,title,10,3,UDim.new(1,-20),20,bold,11,mint)
	local box=make("TextBox",field,{Name=name,Position=UDim2.fromOffset(10,24),Size=UDim2.new(1,-20,0,44),BackgroundTransparency=1,Text=value,PlaceholderText=placeholder,PlaceholderColor3=muted,TextColor3=ivory,TextSize=16,Font=bold,ClearTextOnFocus=false,Selectable=true,TextXAlignment=Enum.TextXAlignment.Left,MultiLine=false})
	box.SelectionGained:Connect(function() revealSelection(box) end)
	box:GetPropertyChangedSignal("Text"):Connect(function() onChange(box.Text:sub(1,12)) end)
	return box
end
-- Confirmation pattern shared with the Market page: review, then Confirm or Cancel.
function U.review()
	local confirm=U.confirm
	if not confirm then return false end
	row(confirm.title,confirm.detail,"Confirm",function()
		U.confirm=nil
		send(confirm.verb,confirm.payload)
	end)
	row("Keep deciding","Cancel this review without placing anything.","Cancel",function() U.confirm=nil;render() end)
	return true
end
function U.ask(title,detail,verb,payload)
	U.confirm={title=title,detail=detail,verb=verb,payload=payload}
	scroll.CanvasPosition=Vector2.zero
	render()
end
function U.refresh(section,quiet)
	if not send or state.ironman then return end
	if section=="Orders" then send("bazaar",U.item,quiet)
	elseif section=="Auctions" then send("ahBrowse",U.cat..":"..U.page,quiet) end
end
function U.depthLines(view)
	local lines={}
	local asks,bids=tbl(view.asks),tbl(view.bids)
	for i=math.min(5,#asks),1,-1 do
		local level=tbl(asks[i])
		table.insert(lines,paint("ASK  "..fmt(level.price).."  ×"..fmt(level.qty),"E8806A").."  ·  "..fmt(level.orders).." order"..(num(level.orders,0)==1 and "" or "s"))
	end
	if #asks==0 then table.insert(lines,paint("No sell offers","E8806A")) end
	table.insert(lines,paint("— spread "..(view.spread and fmt(view.spread).." coins" or "—").." —","F9CC77"))
	for i=1,math.min(5,#bids) do
		local level=tbl(bids[i])
		table.insert(lines,paint("BID  "..fmt(level.price).."  ×"..fmt(level.qty),"9EE7D2").."  ·  "..fmt(level.orders).." order"..(num(level.orders,0)==1 and "" or "s"))
	end
	if #bids==0 then table.insert(lines,paint("No buy orders","9EE7D2")) end
	return lines
end
function U.drawOrders()
	heading("BAZAAR    /    STANDING ORDERS")
	if state.ironman then row("Sealed charter","Player trading is unavailable in Ironman.");return end
	local rules,econ=U.rules(),U.economy()
	if U.review() then return end
	sectionBar(rules.groups,U.group,function(name)
		U.group=name
		local first=U.commodities(name)[1]
		if first then U.item=first;U.refresh("Orders") end
		render()
	end,{small=true,prefix="Group",maxPer=5})
	local list=U.commodities(U.group)
	if #list==0 then card({motif="Ledger",title="Field guide loading…",detail="Commodity records have not arrived yet."});return end
	if not table.find(list,U.item) then U.item=list[1] end
	local size=compactAtlas and 48 or 58
	local grid=gridHolder(UDim2.fromOffset(size,size),6)
	for i,id in ipairs(list) do
		local on=id==U.item
		local cell=tile(grid,"Commodity"..id,i,function()
			U.item=id
			U.confirm=nil
			render()
			U.refresh("Orders")
		end)
		make("UIStroke",cell,{Color=on and gold or slate,Transparency=on and 0 or .5,Thickness=on and 2 or 1})
		local art=itemIcon(cell,id,size-10)
		art.Position=UDim2.fromOffset(5,5)
	end
	local item=U.item
	local def=itemDef(item)
	local view=tbl(econ.bazaar)
	local fresh=view.item==item
	local held=count("items",item)
	card({name="Book",item=item,title=escape(itemName(item)),titleColor=rgb(itemHex(item)),
		subtitle="Held ×"..fmt(held).."  ·  merchant "..fmt(num(def and def.value,0)).." each",
		badge=fresh and view.bestBid and (fmt(view.bestBid).." bid") or nil,badgeColor=mint,
		detail=fresh and ("Best ask "..(view.bestAsk and fmt(view.bestAsk) or "—").."  ·  best bid "..(view.bestBid and fmt(view.bestBid) or "—").."  ·  spread "..(view.spread and fmt(view.spread) or "—")..". Prices are per unit; your own orders are excluded from the best prices.") or "Refresh to read this order book.",
		lines=fresh and U.depthLines(view) or nil,
		actions={{caption="Refresh",fn=function() U.refresh("Orders") end}}})
	heading("PLACE    /    QUANTITY AND UNIT PRICE")
	U.field("QUANTITY (1–"..rules.maxQuantity..")","BazaarQuantity",U.qty,"Whole units",function(value) U.qty=value end)
	U.field("UNIT PRICE (1–"..fmt(rules.maxPrice)..")","BazaarPrice",U.price,"Whole coins per unit",function(value) U.price=value end)
	local function inputs(needPrice)
		local qty=U.whole(U.qty,1,rules.maxQuantity)
		local price=U.whole(U.price,1,rules.maxPrice)
		if not qty then notify("Choose a quantity from 1 to "..rules.maxQuantity..".");return nil end
		if needPrice and not price then notify("Choose a whole unit price from 1 to "..fmt(rules.maxPrice).." coins.");return nil end
		return qty,price
	end
	local name=itemName(item)
	card({name="Place",motif="Ledger",title="Buy order or sell offer",subtitle=fmt(#tbl(econ.orders)).." / "..rules.orderCap.." open orders",
		detail="A buy order escrows quantity × price from your purse and fills when players sell. A sell offer escrows goods from your satchel. Crossing orders fill immediately at the resting price.",
		actions={
			{caption="Buy order",primary=true,fn=function()
				local qty,price=inputs(true)
				if not qty then return end
				if num(state.coins,0)<qty*price then notify("Your purse needs "..fmt(qty*price).." coins to escrow this order.");return end
				U.ask("Review buy order","Buy up to "..qty.." "..name.." at "..fmt(price).." each. "..fmt(qty*price).." coins are escrowed now; anything filled below your price is refunded, and the rest can be cancelled for a refund.","bid",item..":"..qty..":"..price)
			end},
			{caption="Sell offer",fn=function()
				local qty,price=inputs(true)
				if not qty then return end
				if held<qty then notify("You hold "..fmt(held).." "..name..".");return end
				U.ask("Review sell offer","Offer "..qty.." "..name.." at "..fmt(price).." each. The goods are escrowed until sold or cancelled; collect coins with Claim.","offer",item..":"..qty..":"..price)
			end},
		}})
	card({name="Instant",motif="Ledger",title="Instant trade",subtitle=fresh and ("Best bid "..(view.bestBid and fmt(view.bestBid) or "—").."  ·  best ask "..(view.bestAsk and fmt(view.bestAsk) or "—")) or "Refresh for current prices",
		detail="Instant sell fills the highest buy orders (oldest first at equal price) down to your unit price, or any price if blank. Buy now fills the lowest offers up to your price; nothing rests.",
		actions={
			{caption="Instant sell",primary=true,fn=function()
				local qty=U.whole(U.qty,1,rules.maxQuantity)
				if not qty then notify("Choose a quantity from 1 to "..rules.maxQuantity..".");return end
				if held<qty then notify("You hold "..fmt(held).." "..name..".");return end
				local floor=U.whole(U.price,1,rules.maxPrice)
				local estimate=fresh and view.bestBid and (" Best bid now: "..fmt(view.bestBid).." each.") or ""
				U.ask("Review instant sell","Sell up to "..qty.." "..name..(floor and (" at no less than "..fmt(floor).." each") or " to the highest bids").."."..estimate.." Unsold units are returned.","sellToBid",item..":"..qty..(floor and (":"..floor) or ""))
			end},
			{caption="Buy now",fn=function()
				local qty,price=inputs(true)
				if not qty then return end
				if num(state.coins,0)<qty*price then notify("Your purse needs "..fmt(qty*price).." coins for this limit.");return end
				U.ask("Review buy now","Buy up to "..qty.." "..name.." at no more than "..fmt(price).." each. Unfilled coins are returned immediately.","buyNow",item..":"..qty..":"..price)
			end},
		}})
	heading("YOUR ORDERS    /    CLAIM AND CANCEL")
	local orders=tbl(econ.orders)
	if fresh and (num(view.claimUnits,0)>0 or num(view.claimCoins,0)>0) then
		row("Filled and ready",fmt(view.claimUnits).." "..name.." and "..fmt(view.claimCoins).." coins are waiting.","Claim",function() send("bidClaim",item) end)
	end
	if #orders==0 then row("No open orders","Orders you place appear here. Filled goods and sale coins are collected with Claim.") end
	for index,o in ipairs(orders) do
		if index>12 then break end
		o=tbl(o)
		local oid,oitem=o.id,o.item
		if type(oitem)=="string" and type(oid)=="number" then
			local buy=o.side=="bid"
			card({name="Order"..oid,item=oitem,title=(buy and "Buy " or "Sell ")..escape(itemName(oitem)),titleColor=rgb(itemHex(oitem)),
				subtitle="#"..oid.."  ·  "..fmt(o.qty).." open at "..fmt(o.price).." each",badge=buy and "BID" or "ASK",badgeColor=buy and mint or ember,
				actions={{caption="Claim",fn=function() send("bidClaim",oitem) end},{caption="Cancel",fn=function() send("bidCancel",oitem..":"..oid) end}}})
		end
	end
	if econ.pending==true then row("Order recovering","Your last order is still being recorded. Any Bazaar action finishes it first.") end
	row("How matching works",type(view.matchingPolicy)=="string" and view.matchingPolicy or "Highest bid and lowest offer fill first; equal prices fill oldest first.")
end
function U.listable()
	local d=depth()
	local bag=tbl(d and d.accessoryBag)
	local enchants=tbl(d and d.enchants)
	local set={}
	for _,kind in ipairs(U.rules().categories) do set[kind]=true end
	local list={}
	for id,n in pairs(tbl(state.items)) do
		local def=itemDef(id)
		if num(n,0)>0 and def and set[def.kind] and not equippedSlotOf(id) and not table.find(bag,id) and not next(tbl(enchants[id])) then table.insert(list,id) end
	end
	table.sort(list,function(a,b) return itemName(a)<itemName(b) end)
	return list
end
function U.drawAuctions()
	heading("AUCTION HOUSE    /    BUY IT NOW")
	if state.ironman then row("Sealed charter","Player trading is unavailable in Ironman.");return end
	local rules,econ=U.rules(),U.economy()
	if U.review() then return end
	local names,keys={},{}
	for _,kind in ipairs(rules.categories) do table.insert(names,rules.names[kind] or kind);keys[rules.names[kind] or kind]=kind end
	sectionBar(names,rules.names[U.cat] or U.cat,function(name)
		U.cat=keys[name] or "weapon"
		U.page=1
		render()
		U.refresh("Auctions")
	end,{small=true,prefix="Auction",maxPer=5})
	local view=tbl(econ.auction)
	local fresh=view.category==U.cat
	if not fresh then
		row((rules.names[U.cat] or U.cat).." listings","Read the current buy-it-now listings in this category.","Refresh",function() U.refresh("Auctions") end)
	else
		local listings=tbl(view.listings)
		if #listings==0 then row("No listings","Nothing is listed in "..(rules.names[U.cat] or U.cat).." right now.","Refresh",function() U.refresh("Auctions") end) end
		for _,l in ipairs(listings) do
			l=tbl(l)
			local lid,litem,price=l.id,l.item,num(l.price,0)
			if type(litem)=="string" and type(lid)=="number" then
				local def=itemDef(litem)
				card({name="Listing"..lid,item=litem,title=escape(itemName(litem)),titleColor=rgb(itemHex(litem)),
					subtitle=escape((def and def.rarity or "Common").." "..kindLabel(def)).."  ·  "..clock(l.remaining).." left",
					badge=fmt(price).." ¢",badgeColor=gold,detail=def and def.stats and statText(def.stats) or nil,
					actions={l.own and {caption="Yours",disabled=true,reason="You cannot buy your own listing.",fn=function() end}
						or {caption="Buy",primary=true,fn=function()
							if num(state.coins,0)<price then notify("Your purse needs "..fmt(price).." coins.");return end
							U.ask("Review purchase","Buy "..itemName(litem).." for "..fmt(price).." coins. It goes straight to your satchel; if it already sold, your coins are returned.","ahBuy",U.cat..":"..lid..":"..price)
						end}}})
			end
		end
		local pages=num(view.pages,1)
		card({name="Pager",motif="Ledger",title="Page "..fmt(view.page).." of "..fmt(pages),subtitle=fmt(view.total).." active listings · cheapest first",
			actions={{caption="Previous",disabled=num(view.page,1)<=1,reason="This is the first page.",fn=function() U.page=math.max(1,num(view.page,1)-1);U.refresh("Auctions") end},
				{caption="Next",disabled=num(view.page,1)>=pages,reason="This is the last page.",fn=function() U.page=num(view.page,1)+1;U.refresh("Auctions") end}}})
		if num(view.proceeds,0)>0 or num(view.returns,0)>0 then
			row("Ready to collect",fmt(view.proceeds).." coins of sales and "..fmt(view.returns).." expired item(s) in "..(rules.names[U.cat] or U.cat)..".","Claim",function() send("ahClaim",U.cat) end)
		end
	end
	heading("SELL    /    LIST FROM YOUR SATCHEL")
	local listable=U.listable()
	if #listable==0 then
		row("Nothing to list","Unequipped, unenchanted gear, tools, accessories and pet items from your satchel can be listed. Unequip or remove from your accessory bag first.")
	else
		if U.listItem and not table.find(listable,U.listItem) then U.listItem=nil end
		local size=compactAtlas and 48 or 58
		local grid=gridHolder(UDim2.fromOffset(size,size),6)
		for i,id in ipairs(listable) do
			local on=id==U.listItem
			local cell=tile(grid,"Listable"..id,i,function() U.listItem=if U.listItem==id then nil else id;render() end)
			make("UIStroke",cell,{Color=on and gold or slate,Transparency=on and 0 or .5,Thickness=on and 2 or 1})
			local art=itemIcon(cell,id,size-10)
			art.Position=UDim2.fromOffset(5,5)
		end
		local chosen=U.listItem
		if chosen then
			U.field("BUY-IT-NOW PRICE","AuctionPrice",U.listPrice,"1–"..fmt(rules.maxPrice).." whole coins",function(value) U.listPrice=value end)
			local price=U.whole(U.listPrice,1,rules.maxPrice)
			local fee=price and U.fee(price)
			card({name="ListPreview",item=chosen,title=escape(itemName(chosen)),titleColor=rgb(itemHex(chosen)),
				subtitle=price and ("Fee "..fmt(fee).." coins ("..rules.feePercent.."%, not refunded)") or "Enter a price to preview the fee",
				detail="Listings last 24 hours; unsold items return through Claim. "..fmt(#tbl(econ.listings)).." / "..rules.listingCap.." listings used.",
				actions={{caption="Review listing",primary=true,fn=function()
					local p=U.whole(U.listPrice,1,rules.maxPrice)
					if not p then notify("Choose a whole price from 1 to "..fmt(rules.maxPrice).." coins.");return end
					if num(state.coins,0)<U.fee(p) then notify("The listing fee is "..fmt(U.fee(p)).." coins.");return end
					U.ask("Review listing","List one "..itemName(chosen).." for "..fmt(p).." coins. The "..fmt(U.fee(p)).."-coin listing fee is spent now and is not refunded on cancel or expiry.","ahList",chosen..":"..p)
				end}}})
		end
	end
	heading("YOUR LISTINGS")
	local mine=tbl(econ.listings)
	if #mine==0 then row("No listings","Your listings appear here until sold, cancelled or claimed.") end
	local now=num(econ.serverTime,0)
	for index,l in ipairs(mine) do
		if index>12 then break end
		l=tbl(l)
		local lid,litem,cat=l.id,l.item,l.cat
		if type(litem)=="string" and type(lid)=="number" and type(cat)=="string" then
			local left=num(l.expires,0)-now
			card({name="Mine"..lid,item=litem,title=escape(itemName(litem)),titleColor=rgb(itemHex(litem)),
				subtitle=fmt(l.price).." coins  ·  "..(left>0 and (clock(left).." left") or "expired — claim to return"),
				actions={{caption="Claim",fn=function() send("ahClaim",cat) end},{caption="Cancel",disabled=left<=0,reason="Expired listings return through Claim.",fn=function() send("ahCancel",cat..":"..lid) end}}})
		end
	end
	if econ.pending==true then row("Order recovering","Your last order is still being recorded. Any Auction House action finishes it first.") end
end
Pages.drawOrders,Pages.drawAuctions,Pages.econ=U.drawOrders,U.drawAuctions,U
Pages.drawBank,Pages.drawMarket,Pages.drawMerchant,Pages.drawCoop=drawBank,drawMarket,drawMerchant,drawCoop
end

------------------------------------------------------------------------------
-- Navigation: six primary tabs, each with a section switcher.
------------------------------------------------------------------------------
local tabOrder={"Journal","Hero","Satchel","Workshop","Hunt","Ledger"}
local sectionLists={
	Journal={"Bearing","Quests","Diaries","Construction","Regions","Crew"},
	Hero={"Skills","Gear","Enchant","Accessories","Pets"},
	Satchel={"Items","Collections"},
	Workshop={"Forge","Hearth","Cauldron","Workbench","Workers","Home"},
	Hunt={"Slayer","Bestiary","Dungeon"},
	Ledger={"Bank","Market","Orders","Auctions","Merchant"},
}
sectionOf={Journal="Bearing",Hero="Skills",Satchel="Items",Workshop="Forge",Hunt="Slayer",Ledger="Bank"}
local drawers={
	Journal={Bearing=Pages.drawBearing,Quests=Pages.drawQuests,Diaries=Pages.drawDiaries,Construction=Pages.drawConstruction,Regions=Pages.drawRegions,Crew=Pages.drawCoop},
	Hero={Skills=Pages.drawSkills,Gear=Pages.drawGear,Enchant=Pages.drawEnchant,Accessories=Pages.drawAccessories,Pets=Pages.drawPets},
	Satchel={Items=Pages.drawItems,Collections=Pages.drawCollections},
	Workshop={Forge=function() Pages.drawStation("Forge") end,Hearth=function() Pages.drawStation("Hearth") end,Cauldron=function() Pages.drawStation("Cauldron") end,
		Workbench=function() Pages.drawStation("Workbench") end,Workers=Pages.drawWorkers,Home=Pages.drawHome},
	Hunt={Slayer=Pages.drawSlayer,Bestiary=Pages.drawBestiary,Dungeon=Pages.drawDungeon},
	Ledger={Bank=Pages.drawBank,Market=Pages.drawMarket,Orders=Pages.drawOrders,Auctions=Pages.drawAuctions,Merchant=Pages.drawMerchant},
}
local function resetTransient()
	confirmIron=false
	coopConfirm=nil
	sellConfirm=nil
	abandonConfirm=false
	purchaseReview=nil
	if Pages.econ then Pages.econ.confirm=nil end
	Pages.resetJournal()
end
local function refreshSection(tab,section)
	if tab=="Journal" and section=="Crew" and sendCoop then sendCoop("state") end
	if tab=="Ledger" and section=="Market" and send and not state.ironman then send("market",marketItem) end
	if tab=="Ledger" and Pages.econ then Pages.econ.refresh(section) end
end
local function drawPage()
	local tab=current
	sectionBar(sectionLists[tab],sectionOf[tab],function(name)
		sectionOf[tab]=name
		resetTransient()
		scroll.CanvasPosition=Vector2.zero
		render()
		refreshSection(tab,name)
	end,{prefix="Section"})
	local drawer=drawers[tab] and drawers[tab][sectionOf[tab]]
	if drawer then drawer() end
end
local function layoutTabs()
	local n=#tabOrder
	for i,name in ipairs(tabOrder) do
		local b=tabButtons[name]
		if b then
			local icon=b:FindFirstChild("TabIcon")
			local caption=b:FindFirstChild("TabCaption")
			if railMode then
				b.Position=UDim2.new(0,0,(i-1)/n,0)
				b.Size=UDim2.new(1,0,1/n,-4)
				if icon then icon.Size=UDim2.fromOffset(18,18);icon.Position=UDim2.new(0,5,.5,-9) end
				if caption then caption.Position=UDim2.fromOffset(26,0);caption.Size=UDim2.new(1,-28,1,0);caption.TextXAlignment=Enum.TextXAlignment.Left end
			else
				b.Position=UDim2.new((i-1)/n,0,0,0)
				b.Size=UDim2.new(1/n,-3,1,0)
				if icon then icon.Size=UDim2.fromOffset(compactAtlas and 18 or 23,compactAtlas and 18 or 23);icon.Position=UDim2.new(.5,compactAtlas and -9 or -11,0,compactAtlas and 2 or 4) end
				if caption then caption.Position=UDim2.fromOffset(2,compactAtlas and 22 or 30);caption.Size=UDim2.new(1,-4,0,20);caption.TextXAlignment=Enum.TextXAlignment.Center end
			end
			b.BackgroundColor3 = name == current and mint or slate
			b.TextColor3 = name == current and deep or ivory
			if caption then caption.TextColor3=name==current and deep or ivory end
		end
	end
end
local function updateVitals() end
render = function(fromPush)
	local size=atlas.AbsoluteSize
	compactAtlas=size.X<480 or size.Y<500
	if THUMBS.compact~=compactAtlas then
		THUMBS.compact=compactAtlas
		THUMBS.trim()
	end
	railMode=compactAtlas and size.X>=560 and size.X>size.Y*1.3
	local headHeight=railMode and 46 or (compactAtlas and 64 or 88)
	head.Size=UDim2.new(1,0,0,headHeight)
	mastheadCaption.Visible=not compactAtlas
	guildLabel.Visible=not railMode
	compassBadge.Size=UDim2.fromOffset(railMode and 32 or 43,railMode and 32 or 43)
	compassBadge.Position=UDim2.fromOffset(railMode and 8 or 13,railMode and 7 or 10)
	titleLabel.Position=UDim2.fromOffset(railMode and 48 or 67,railMode and 6 or 24)
	titleLabel.TextSize=railMode and 22 or 27
	closeButton.Position=railMode and UDim2.new(1,-58,0,4) or UDim2.new(1,-64,0,10)
	closeButton.Size=railMode and UDim2.fromOffset(50,38) or UDim2.fromOffset(54,43)
	if railMode then
		tabs.Position=UDim2.fromOffset(8,headHeight+6)
		tabs.Size=UDim2.new(0,98,1,-headHeight-12)
		scroll.Position=UDim2.fromOffset(114,headHeight+6)
		scroll.Size=UDim2.new(1,-122,1,-headHeight-12)
		footer.Visible=false
	else
		tabs.Position=UDim2.fromOffset(10,compactAtlas and 70 or 96)
		tabs.Size=UDim2.new(1,-20,0,compactAtlas and 44 or 56)
		local contentTop=compactAtlas and 122 or 160
		scroll.Position=UDim2.fromOffset(12,contentTop)
		scroll.Size=UDim2.new(1,-24,1,-contentTop-37)
		footer.Visible=true
	end
	purse.Text = synced and ((state.ironman and "Ironman" or "Voyager") .. "   ·   " .. fmt(num(state.coins,0)) .. " coins")
		or "Opening ledger…"
	instruction.Text = synced and nextGoal() or "Charting the islands…"
	updateVitals()
	if not atlas.Visible then
		return
	end
	-- A pushed snapshot must not destroy the TextBox being typed in; redraw once
	-- focus is released instead.
	-- (THUMBS.deferred doubles as the pending-redraw flag to spare a top-level local.)
	if fromPush==true then
		local ok,box=pcall(Input.GetFocusedTextBox,Input)
		if ok and box~=nil and box:IsDescendantOf(atlas) then
			THUMBS.deferred=true
			return
		end
	end
	THUMBS.deferred=false
	local selectedObject=GuiService.SelectedObject
	local restoreFocus=selectedObject and selectedObject:IsDescendantOf(scroll)
	local selectionName=restoreFocus and selectedObject.Name
	local selectionClass=restoreFocus and selectedObject.ClassName
	releaseViews(scroll)
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	order = 0
	thumbnailCount = 0
	layoutTabs()
	if synced then
		local ok,problem=pcall(drawPage)
		if not ok then
			warn("Atlas page failed: "..tostring(problem))
			card({motif="Journal",title="This page hit a snag",titleColor=gold,detail="Some records could not be drawn. Try another section or reopen the atlas."})
		end
	else
		heading("OPENING YOUR LEDGER…")
	end
	if restoreFocus then
		local replacement
		for _,object in scroll:GetDescendants() do
			if object.Name==selectionName and object.ClassName==selectionClass and object:IsA("GuiObject") and object.Selectable then replacement=object;break end
		end
		GuiService.SelectedObject=replacement or tabButtons[current]
	end
	footer.Text = state.preview and "STUDIO PRACTICE     /     PROGRESS IS TEMPORARY"
		or "AETHER ISLES     /     FIELD EDITION"
end
for _, name in ipairs(tabOrder) do
	local b = button(tabs, name, UDim2.new(), UDim2.new(1/#tabOrder, -3, 1, 0), function()
		current = name
		resetTransient()
		scroll.CanvasPosition = Vector2.zero
		render()
		refreshSection(name,sectionOf[name])
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
	make("UITextSizeConstraint",tabCaption,{MinTextSize=11,MaxTextSize=13})
	b.TextSize = 13
	b.TextScaled = true
	make("UITextSizeConstraint", b, {MinTextSize=10,MaxTextSize=13})
	tabButtons[name] = b
end
layoutTabs()
atlas:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if atlas.Visible then render() end end)
openAtlas = function()
	atlas.Visible = true
	atlas.Position=UDim2.new(.5,0,.5,8)
	TweenService:Create(atlas,TweenInfo.new(.18,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.fromScale(.5,.5)}):Play()
	hud.Visible = false
	actionBar.Visible = false
	shade.Visible = true
	render()
	if send then send("state") end
	refreshSection(current,sectionOf[current])
	if Input.GamepadEnabled then
		GuiService.SelectedObject = tabButtons[current]
	end
end
local function openTo(tab,section)
	current=tab
	if section then sectionOf[tab]=section end
	resetTransient()
	scroll.CanvasPosition=Vector2.zero
	openAtlas()
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

------------------------------------------------------------------------------
-- Action bar: live health/defense and XP-gain popups; level-up celebration.
------------------------------------------------------------------------------
local humanoid
updateVitals=function()
	local stats=tbl(dget("stats"))
	local legacy=tbl(state.stats)
	local maxHealth=humanoid and num(humanoid.MaxHealth,nil) or num(stats.health,nil) or num(legacy.maxHealth,nil)
	local health=humanoid and num(humanoid.Health,nil) or maxHealth
	healthText.Text=maxHealth and ("❤ "..fmt(math.max(0,math.floor(health or 0))).."/"..fmt(math.floor(maxHealth))) or "❤ —"
	local defense=num(stats.defense,nil) or num(legacy.defense,nil)
	defenseText.Text=defense and ("❈ "..fmt(defense).." Defense") or "❈ —"
end
local function watchCharacter(character)
	if not character then return end
	local found=character:WaitForChild("Humanoid",10)
	if not found or not found:IsA("Humanoid") then return end
	humanoid=found
	found.HealthChanged:Connect(function() if humanoid==found then updateVitals() end end)
	found:GetPropertyChangedSignal("MaxHealth"):Connect(function() if humanoid==found then updateVitals() end end)
	updateVitals()
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then task.spawn(watchCharacter,player.Character) end
local xpToken=0
local function showXp(text,color)
	xpToken+=1
	local token=xpToken
	xpText.Text=text
	xpText.TextColor3=color or gold
	xpText.TextTransparency=0
	task.delay(2.6,function()
		if token==xpToken then TweenService:Create(xpText,TweenInfo.new(.4),{TextTransparency=1}):Play() end
	end)
end
local bannerQueue,bannerBusy={},false
local function showNextBanner()
	local entry=table.remove(bannerQueue,1)
	if not entry then bannerBusy=false;banner.Visible=false;return end
	bannerBusy=true
	-- Narrow screens: keep the banner clear of the touch attack button (bottom right).
	local view=gui.AbsoluteSize
	banner:FindFirstChild("BannerLimit").MaxSize=Vector2.new(view and view.X<900 and 340 or 420,74)
	local hex=skillHex(entry.skill)
	bannerTitle.Text=entry.skill.."  "..entry.from.."  →  "..entry.to
	bannerTitle.TextColor3=rgb(lighten(hex,.35))
	local reward=entry.coins>0 and paint("+"..fmt(entry.coins).." coins","F9CC77") or ""
	local stats=statText(skillDef(entry.skill).perLevel,entry.to-entry.from,"  ")
	bannerReward.Text=reward..(reward~="" and stats~="" and "   ·   " or "")..stats
	banner.Visible=true
	bannerScale.Scale=.82
	TweenService:Create(bannerScale,TweenInfo.new(.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
	task.delay(3.4,showNextBanner)
end
local function celebrate(before,after)
	local gains,bannered={},{}
	for _,skill in ipairs(skillOrder()) do
		local old,new=before[skill],after[skill]
		if old and new and new.xp>old.xp then
			table.insert(gains,{skill=skill,amount=new.xp-old.xp,info=new})
			if new.level>old.level then
				local coins=0
				if Data and type(Data.levelCoinReward)=="function" then
					for level=old.level+1,new.level do
						local ok,value=pcall(Data.levelCoinReward,level)
						if ok then coins+=num(value,0) end
					end
				end
				table.insert(bannerQueue,{skill=skill,from=old.level,to=new.level,coins=coins})
				if coins>0 then bannered[skill]=true end
			end
		end
	end
	if #gains>0 then
		local parts={}
		for i=1,math.min(compactAtlas and 1 or 3,#gains) do
			local gain=gains[i]
			local percent=gain.info.maxed and "MAX" or (math.floor(gain.info.fraction*1000+.5)/10 .."%")
			table.insert(parts,paint("+"..fmt(gain.amount).." "..gain.skill,lighten(skillHex(gain.skill),.35))..paint(" ("..percent..")","FFF4D9"))
		end
		showXp(table.concat(parts,"   "))
	end
	if #bannerQueue>0 and not bannerBusy then showNextBanner() end
	return bannered
end


------------------------------------------------------------------------------
-- Server wiring
------------------------------------------------------------------------------
local remote = ReplicatedStorage:WaitForChild("IsleAction")
local updates = ReplicatedStorage:WaitForChild("IsleUpdate")
local function accept(data,quiet)
	if type(data) ~= "table" or type(data.items) ~= "table" then
		if type(data) == "table" then
			notify(data.message)
		end
		return false
	end
	if type(data.market)=="table" and type(data.market.item)=="string" then
		local quote=data.market
		local previous=marketQuotes[quote.item]
		if previous and previous.bestAsk~=quote.bestAsk then
			marketChanges[quote.item]="Best ask changed from "..(previous.bestAsk and (previous.bestAsk.." coins") or "no offers").." to "..(quote.bestAsk and (quote.bestAsk.." coins") or "no offers").."."
		end
		marketQuotes[quote.item]=quote
	end
	local before=synced and skillsOf(state) or nil
	state = data
	synced = true
	render(true)
	local message=data.message
	if before then
		local ok,bannered=pcall(celebrate,before,skillsOf(state))
		if not ok then warn("XP popup failed: "..tostring(bannered))
		elseif type(bannered)=="table" and type(message)=="string" and next(bannered) then
			-- The server appends "<Skill> level N! +X coins"; the level-up banner already
			-- announces those coins, so drop that segment from the toast.
			local kept={}
			for segment in (message.."   ·   "):gmatch("(.-)   ·   ") do
				local skill=segment:match("^(%a+) level %d+! %+[%d,]+ coins$")
				if not (skill and bannered[skill]) and segment~="" then table.insert(kept,segment) end
			end
			message=table.concat(kept,"   ·   ")
		end
	end
	if not quiet then notify(message) end
	return true
end
local pending = false
send = function(action, item, quiet)
	if pending then
		return
	end
	pending = true
	local ok, result = pcall(function()
		return remote:InvokeServer(action, item)
	end)
	pending = false
	if ok then
		accept(result,quiet)
	else
		notify("Your ledger could not be reached. Try again.")
	end
end
local function acceptCoop(result)
	if type(result) ~= "table" or type(result.members) ~= "table" then return false end
	coopState = result
	coopError = nil
	if result.groupId then coopConfirm = nil end
	render(true)
	notify(result.message)
	return true
end
sendCoop = function(verb, item, extra)
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
	local ok, result = pcall(function() return remoteCoop:InvokeServer(verb,item,extra) end)
	coopPending = false
	if not (ok and acceptCoop(result)) then
		coopError = if ok and type(result) == "table" and type(result.message) == "string" then result.message else "The shared ledger could not be reached. Refresh before trying again."
	end
	render()
end
-- Crafting stations and the slayer board set IsleStation on the player; open
-- the matching page. Values may carry a suffix ("Forge:3") so repeats fire.
local stationTabs={Forge="Workshop",Hearth="Workshop",Cauldron="Workshop",Workbench="Workshop",Slayer="Hunt",Construction="Journal"}
local function openStation()
	local value=player:GetAttribute("IsleStation")
	if type(value)~="string" then return end
	local station=value:match("^(%a+)")
	local tab=station and stationTabs[station]
	if not tab then return end
	if tab=="Workshop" then openTo("Workshop",station) elseif tab=="Journal" then openTo("Journal","Construction") else openTo("Hunt","Slayer") end
end
-- World sets IsleStation and then bumps IsleStationVisit on every trigger; only the
-- counter opens the atlas, so each visit opens it exactly once (repeats included).
player:GetAttributeChangedSignal("IsleStationVisit"):Connect(openStation)
-- Denied region warps explain themselves with a toast. World sets the message and
-- then bumps IsleRegionNoticeCount, so an identical repeated denial still shows.
player:GetAttributeChangedSignal("IsleRegionNoticeCount"):Connect(function()
	local message=player:GetAttribute("IsleRegionNotice")
	if type(message)=="string" and message~="" then notify(message) end
end)
-- Snapshots pushed while typing were deferred; draw the latest one now.
Input.TextBoxFocusReleased:Connect(function()
	if THUMBS.deferred then
		THUMBS.deferred=false
		task.defer(render)
	end
end)
task.spawn(function()
	ReplicatedStorage:WaitForChild("IsleCoopUpdate").OnClientEvent:Connect(acceptCoop)
end)
task.spawn(function()
	while task.wait(5) do
		if synced and atlas.Visible and current=="Ledger" and sectionOf.Ledger=="Market" and not state.ironman and not Input:GetFocusedTextBox() then send("market",marketItem,true) end
		if synced and atlas.Visible and current=="Ledger" and Pages.econ and not Pages.econ.confirm and not Input:GetFocusedTextBox() then Pages.econ.refresh(sectionOf.Ledger,true) end
	end
end)
task.spawn(function()
	-- Keep the action bar's health readout fresh between snapshots.
	while task.wait(1) do
		updateVitals()
	end
end)
updates.OnClientEvent:Connect(accept)
while not synced do
	send("state")
	if not synced then
		task.wait(2)
	end
end
