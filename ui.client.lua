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
	if class == "UICorner" then
		local r = object.CornerRadius
		if r and r.Scale == 0 and r.Offset > 7 then object.CornerRadius = UDim.new(0, if r.Offset >= 12 then 7 else 5) end
	end
	object.Parent = parent
	return object
end
local function rgb(hex)
	return Color3.fromHex(hex)
end
------------------------------------------------------------------------------
-- "Skyforge" design system: every token comes from the shared theme
-- (shared/UiTheme.lua → ReplicatedStorage.AetherUiTheme, §29), which the HUD,
-- satchel, Wayfinder and hotbar use too.
-- Surfaces, darkest to brightest: track (wells, bar tracks) < deep (cards,
-- tiles) < ink (window body) < slate (controls) < UI.raised (hover/selected).
-- Bronze frames with gold top light and corner studs frame the important
-- surfaces; mint marks state, gold marks primary actions and headings, ember
-- marks danger/locked. Type: pixel display face (Arcade) for titles, section
-- heads and counters; Builder Sans ExtraBold/Bold/Medium for everything read.
-- Spacing on a 4px grid (4/8/12/16); square-ish corners (radius <= 7).
-- Tokens and helpers live in one table (UI): this chunk sits at Luau's 200
-- top-level local limit.
------------------------------------------------------------------------------
local UI = {T = require(ReplicatedStorage:WaitForChild("AetherUiTheme"))}
local ink, deep, slate = UI.T.color.panel, rgb("0D141D"), UI.T.color.raised
local ivory, muted, mint, gold = UI.T.color.text, UI.T.color.dim, UI.T.color.mint, UI.T.color.gold
local ember, track = UI.T.color.ember, UI.T.color.void
UI.raised, UI.line, UI.rim, UI.brass, UI.brassDark = UI.T.color.hover, UI.T.color.line, rgb("4A5A6E"), UI.T.color.frame, UI.T.color.frameLo
UI.copy, UI.onGold, UI.white, UI.black = rgb("D6DCE4"), UI.T.color.onGold, Color3.new(1, 1, 1), Color3.new(0, 0, 0)
UI.heavy, UI.display = Enum.Font.BuilderSansExtraBold, UI.T.font.display
UI.TOUCH = 44 -- minimum touch target (px) for every control on phone layouts (compactAtlas)
-- HUD lanes for the current screen (Theme.hudLayout; the hotbar gap included).
function UI.lay()
	local view = (UI.gui and UI.gui.AbsoluteSize) or Vector2.new(1366, 768)
	if view.X <= 0 or view.Y <= 0 then view = Vector2.new(1366, 768) end
	return UI.T.hudLayout(view.X, view.Y, {touch = Input.TouchEnabled, satchelOpen = player:GetAttribute("IsleSatchelOpen") == true})
end
do
	local materials = ReplicatedStorage:FindFirstChild("MaterialArt")
	if materials then
		local ok, data = pcall(require, materials)
		if ok and type(data) == "table" then
			if type(data.gui) == "string" and data.gui ~= "" then UI.clothTexture = data.gui end
			if type(data.getGuiContent) == "function" then
				local ready, content = pcall(data.getGuiContent)
				if ready then UI.clothContent = content end
			end
		end
	end
end
local function panel(parent, position, size, color)
	local textured=(UI.clothContent or UI.clothTexture) and (color==ink or color==deep or color==slate) and (size.X.Scale>0 or size.X.Offset>=32) and (size.Y.Scale>0 or size.Y.Offset>=28)
	local properties={Name="Frame",Position=position,Size=size,BackgroundColor3=color,BorderSizePixel=0}
	if textured then
		if UI.clothContent then properties.ImageContent=UI.clothContent else properties.Image=UI.clothTexture end
		properties.ImageTransparency=.93
		properties.ScaleType=Enum.ScaleType.Tile
		properties.TileSize=UDim2.fromOffset(128,128)
	end
	return make(textured and "ImageLabel" or "Frame",parent,properties)
end
-- Vertical sheen: the fill colour is multiplied from `top` (light catches the
-- upper edge) to `bottom` (shadowed foot).
function UI.sheen(object,top,bottom)
	top,bottom=top or 1,bottom or .74
	return make("UIGradient",object,{Name="Sheen",Rotation=90,Color=ColorSequence.new(Color3.new(top,top,top),Color3.new(bottom,bottom,bottom))})
end
-- Inner bevel: a hairline highlight just inside the rim, bright at the top and
-- fading out towards the bottom.
function UI.bevel(object,radius,transparency)
	local inner=make("Frame",object,{Name="Bevel",BackgroundTransparency=1,Position=UDim2.fromOffset(1,1),Size=UDim2.new(1,-2,1,-2),Active=false,Selectable=false})
	make("UICorner",inner,{CornerRadius=UDim.new(0,math.max(0,radius-1))})
	local line=make("UIStroke",inner,{Color=UI.white,Transparency=transparency or .8,Thickness=1})
	make("UIGradient",line,{Rotation=90,Transparency=NumberSequence.new(0,1)})
	return inner
end
-- Ornamental corners: a brass gem on each corner with L-bracket arms along
-- both edges (built from rotated frames, no images).
function UI.corners(object,color,size,inset)
	if UI.T then return UI.T.ornaments(object,size or 6,inset or 5,color) end
	size,inset=size or 7,inset or 6
	local holder=make("Frame",object,{Name="Ornaments",BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Active=false,Selectable=false})
	local arm=math.floor(size*2.4)
	for _,c in ipairs({{0,0},{1,0},{0,1},{1,1}}) do
		local sx,sy=c[1]==0 and 1 or -1,c[2]==0 and 1 or -1
		make("Frame",holder,{Name="ArmX",AnchorPoint=Vector2.new(c[1],.5),Position=UDim2.new(c[1],sx*(inset+size*.5),c[2],sy*inset),Size=UDim2.fromOffset(arm,1),BackgroundColor3=color,BackgroundTransparency=.3,BorderSizePixel=0})
		make("Frame",holder,{Name="ArmY",AnchorPoint=Vector2.new(.5,c[2]),Position=UDim2.new(c[1],sx*inset,c[2],sy*(inset+size*.5)),Size=UDim2.fromOffset(1,arm),BackgroundColor3=color,BackgroundTransparency=.3,BorderSizePixel=0})
		local gem=make("Frame",holder,{Name="Gem",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(c[1],sx*inset,c[2],sy*inset),Size=UDim2.fromOffset(size,size),Rotation=45,BackgroundColor3=color,BorderSizePixel=0})
		make("UIStroke",gem,{Color=track,Thickness=1,Transparency=.1})
	end
	return holder
end
-- Hairline divider that fades out at both ends.
function UI.rule(parent,color,y,x)
	local line=make("Frame",parent,{Name="Rule",BackgroundColor3=color or UI.brass,BorderSizePixel=0,Position=UDim2.new(0,x or 0,0,y or 0),Size=UDim2.new(1,-2*(x or 0),0,1),Active=false})
	make("UIGradient",line,{Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.18,.2),NumberSequenceKeypoint.new(.82,.2),NumberSequenceKeypoint.new(1,1)})})
	return line
end
-- Brass rim with a light top edge.
local function rounded(object, radius, edge)
	make("UICorner", object, { CornerRadius = UDim.new(0, radius) })
	if edge then
		local rim=make("UIStroke", object, { Color = edge, Transparency = 0.12, Thickness = 1 })
		make("UIGradient",rim,{Color=ColorSequence.new(UI.white,Color3.new(.55,.55,.55)),Rotation=90})
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
local full, bold, book, regular = UDim.new(1, 0), Enum.Font.BuilderSansBold, UI.T.font.display, Enum.Font.BuilderSansMedium
-- Leading action glyph on card buttons (parts named "Cut" take the button fill).
function UI.engrave(parent,caption)
	-- (UIPadding offsets children too: -8 lands the glyph 10px inside the rim.)
	local emblem=make("Frame",parent,{Name="ControlEngraving",AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,-8,.5,0),Size=UDim2.fromOffset(13,13),BackgroundTransparency=1,Active=false})
	local function mark(x,y,w,h,angle,cut)
		local part=make("Frame",emblem,{Name=cut and "Cut" or "Mark",Position=UDim2.fromScale(x,y),Size=UDim2.fromScale(w,h),AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=cut and parent.BackgroundColor3 or parent.TextColor3,BorderSizePixel=0,Rotation=angle or 0,Active=false})
		return part
	end
	if caption=="Craft" or caption=="Build" or caption=="Upgrade" or caption=="Forge" or caption=="Enchant" or caption=="Place" then
		mark(.42,.62,.17,.72,-35);mark(.64,.3,.62,.26,-35)
	elseif caption=="Collect" or caption=="Claim" or caption=="Deposit" or caption=="Withdraw" or caption=="Buy" or caption=="Sell all" or caption=="Sell" or caption=="Begin" or caption=="Trade" or caption=="Claim gift" then
		local coin=mark(.5,.5,.8,.8,0);make("UICorner",coin,{CornerRadius=UDim.new(1,0)});mark(.5,.5,.12,.46,0,true)
	elseif caption=="Confirm" or caption=="Accept" or caption=="Equip" or caption=="Summon" or caption=="Adopt" or caption=="Add" then
		mark(.3,.62,.17,.42,-40);mark(.6,.46,.17,.8,40)
	elseif caption=="Cancel" or caption=="Close" or caption=="Unequip" or caption=="Dismiss" or caption=="Remove" or caption=="Abandon" or caption=="Dismantle" then
		mark(.5,.5,.15,.9,45);mark(.5,.5,.15,.9,-45)
	elseif caption=="Feed" or caption=="Eat" or caption=="Drink" then
		mark(.5,.5,.5,.72,35);mark(.5,.5,.09,.85,35,true)
	else
		mark(.5,.5,.58,.58,45);mark(.5,.5,.22,.22,45,true)
	end
	make("UIPadding",parent,{Name="GlyphPad",PaddingLeft=UDim.new(0,18),PaddingRight=UDim.new(0,4)})
	return emblem
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
-- Gamepad selection: one shared brass ring instead of the default blue box.
UI.ring=make("Frame",nil,{Name="SelectionRing",BackgroundTransparency=1,Size=UDim2.fromScale(1,1)})
make("UICorner",UI.ring,{CornerRadius=UDim.new(0,10)})
make("UIStroke",UI.ring,{Color=gold,Thickness=2.5,Transparency=0})
-- Hover/selection glow: a lazily created white wash tweened in and out.
function UI.hover(b,on)
	local glow=b:FindFirstChild("Hover")
	if not glow then
		if not on then return end
		local corner=b:FindFirstChildOfClass("UICorner")
		glow=make("Frame",b,{Name="Hover",BackgroundColor3=UI.white,BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Active=false,Selectable=false})
		make("UICorner",glow,{CornerRadius=corner and corner.CornerRadius or UDim.new(0,9)})
	end
	TweenService:Create(glow,TweenInfo.new(.12),{BackgroundTransparency=on and .9 or 1}):Play()
end
local function pressable(b)
	local pressScale=make("UIScale",b,{Scale=1})
	b.SelectionImageObject=UI.ring
	b.MouseButton1Down:Connect(function() TweenService:Create(pressScale,TweenInfo.new(.08),{Scale=.96}):Play() end)
	b.MouseButton1Up:Connect(function() TweenService:Create(pressScale,TweenInfo.new(.12,Enum.EasingStyle.Back),{Scale=1}):Play() end)
	b.MouseEnter:Connect(function() UI.hover(b,true) end)
	b.MouseLeave:Connect(function() pressScale.Scale=1;UI.hover(b,false) end)
	b.SelectionGained:Connect(function() revealSelection(b);UI.hover(b,true) end)
	b.SelectionLost:Connect(function() UI.hover(b,false) end)
end
-- Button variants: secondary (default), primary (gold), selected (mint),
-- disabled (sunken) and danger (ember copy).
function UI.tone(b,kind)
	local rim=b:FindFirstChild("Rim")
	if kind=="primary" then
		b.BackgroundColor3,b.TextColor3=gold,UI.onGold
		if rim then rim.Color,rim.Transparency=rgb("FFE7A8"),0 end
	elseif kind=="selected" then
		b.BackgroundColor3,b.TextColor3=mint,deep
		if rim then rim.Color,rim.Transparency=rgb("D8FFF5"),0 end
	elseif kind=="disabled" then
		b.BackgroundColor3,b.TextColor3=ink,muted
		if rim then rim.Color,rim.Transparency=UI.line,.2 end
	else
		b.BackgroundColor3,b.TextColor3=slate,kind=="danger" and rgb("FFB3A4") or ivory
		if rim then rim.Color,rim.Transparency=UI.rim,0 end
	end
	local mark=b:FindFirstChild("ControlEngraving")
	if mark then for _,part in ipairs(mark:GetChildren()) do part.BackgroundColor3=part.Name=="Cut" and b.BackgroundColor3 or b.TextColor3 end end
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
		Font = UI.heavy,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Selectable = true,
	})
	make("UICorner",b,{CornerRadius=UDim.new(0,9)})
	local rim=make("UIStroke",b,{Name="Rim",Color=UI.rim,Thickness=1,Transparency=0})
	make("UIGradient",rim,{Rotation=90,Color=ColorSequence.new(UI.white,Color3.new(.42,.42,.42))})
	UI.sheen(b,1,.8)
	pressable(b)
	b.Activated:Connect(action)
	return b
end
local gui = make(
	"ScreenGui",
	player:WaitForChild("PlayerGui"),
	{ Name = "AetherAtlas", ResetOnSpawn = false, DisplayOrder = 8, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }
)
-- Guild crest: brass ring, compass star (gold cardinals, mint diagonals) and core.
function UI.compass(parent, x, y, size)
	local badge = panel(parent, UDim2.fromOffset(x, y), UDim2.fromOffset(size, size), deep)
	badge.Name="Crest"
	make("UICorner",badge,{CornerRadius=UDim.new(1,0)})
	local rim=make("UIStroke",badge,{Color=UI.brass,Thickness=1.5})
	make("UIGradient",rim,{Rotation=90,Color=ColorSequence.new(rgb("FFE2A0"),rgb("6B4E24"))})
	make("UIGradient",badge,{Rotation=90,Color=ColorSequence.new(rgb("2C5466"),rgb("0A151C"))}).Name="Sheen"
	local ring=make("Frame",badge,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(.74,.74),BackgroundTransparency=1})
	make("UICorner",ring,{CornerRadius=UDim.new(1,0)})
	make("UIStroke",ring,{Color=UI.brass,Thickness=1,Transparency=.45})
	local function blade(w,h,angle,color)
		local part=make("Frame",badge,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(w,h),Rotation=angle,BackgroundColor3=color,BorderSizePixel=0})
		return part
	end
	for _, angle in ipairs({ 45, 135 }) do blade(.07,.62,angle,mint) end
	for _, angle in ipairs({ 0, 90 }) do
		local point=blade(.09,.86,angle,gold)
		make("UIGradient",point,{Rotation=angle==0 and 90 or 0,Color=ColorSequence.new(rgb("FFF1C8"),rgb("C08A3A"))})
	end
	local core=blade(.24,.24,45,ivory)
	make("UIStroke",core,{Color=UI.brassDark,Thickness=1})
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
-- Multipliers and rates (×1.24, ×2.8): at most two decimals, never float noise.
function UI.dec(value) return (string.format("%.2f",num(value,0)):gsub("%.?0+$","")) end
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
local slotNames={weapon="Weapon",helmet="Helmet",chest="Chestplate",legs="Greaves",boots="Boots",pickaxe="Pickaxe",hatchet="Hatchet",rod="Rod",hoe="Hoe",ammo="Quiver"}
local gearSlots={"weapon","helmet","chest","legs","boots"}
local gearSlotSet={weapon=true,helmet=true,chest=true,legs=true,boots=true,ammo=true}
local function kindLabel(def)
	if not def then return "Item" end
	local kind=def.kind
	if kind=="weapon" then return def.style=="ranged" and "Bow" or def.style=="magic" and (type(def.magic)=="table" and #(def.magic.elements or {})==0 and "Wand" or "Staff") or "Weapon"
	elseif kind=="armor" then return slotNames[def.slot] or "Armor"
	elseif def.category=="ammo" then return "Arrows" elseif def.category=="glyph" then return "Glyph" elseif def.category=="tablet" then return "Tablet"
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
-- (compact) layouts get a smaller live/pooled budget. Item icons have their own
-- budget; decorative art (card titles, charts) draws from a small separate share,
-- so page art can never spend the budget item icons need and push them to initials.
-- (Kept in one table: this chunk is close to Luau's 200 top-level local limit.)
local TEMPLATE_LIMIT = 64
local THUMBS = { budget = 24, pool = 48, decor = 6, compactBudget = 14, compactPool = 28, compactDecor = 2, compact = false, decorUsed = 0 }
function THUMBS.limits()
	if THUMBS.compact then return THUMBS.compactBudget, THUMBS.compactPool, THUMBS.compactDecor end
	return THUMBS.budget, THUMBS.pool, THUMBS.decor
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
-- Page/tab glyphs drawn from rotated frames: a raised brass-rimmed plate with
-- a two-tone mark. Tabs strip the plate (BackgroundTransparency 1).
local function motif(parent,kind,size)
	local frame=panel(parent,UDim2.new(),UDim2.fromOffset(size,size),deep)
	make("UICorner",frame,{CornerRadius=UDim.new(0,math.max(4,size//5))})
	local rim=make("UIStroke",frame,{Name="Rim",Color=UI.brass,Thickness=1,Transparency=.35})
	make("UIGradient",rim,{Rotation=90,Color=ColorSequence.new(UI.white,Color3.new(.4,.4,.4))})
	make("UIGradient",frame,{Name="Sheen",Rotation=90,Color=ColorSequence.new(rgb("3A4E68"),rgb("0C121A"))})
	local function stroke(x,y,w,h,angle,color)
		local mark=make("Frame",frame,{Position=UDim2.fromScale(x,y),Size=UDim2.fromScale(w,h),AnchorPoint=Vector2.new(.5,.5),Rotation=angle or 0,BackgroundColor3=color or gold,BorderSizePixel=0})
		return mark
	end
	local function round(mark,r) make("UICorner",mark,{CornerRadius=UDim.new(r or 1,0)}) return mark end
	if kind=="Ledger" then
		for i=1,3 do local coin=round(stroke(.36+i*.08,.74-i*.14,.5,.2,0,i==3 and gold or mint));make("UIStroke",coin,{Color=deep,Thickness=1,Transparency=.3}) end
	elseif kind=="Workshop" then
		stroke(.46,.58,.12,.62,-38,mint);local head=stroke(.6,.32,.56,.2,-38,gold);round(head,.25)
	elseif kind=="Satchel" then
		local bag=round(stroke(.5,.6,.6,.52,0,mint),.35)
		round(stroke(.5,.27,.3,.18,0,gold),.5)
		stroke(.5,.5,.6,.07,0,gold)
		stroke(.5,.58,.12,.14,45,deep)
	elseif kind=="Ration" then
		local parcel=round(stroke(.5,.55,.58,.48,-12,mint),.2)
		stroke(.5,.55,.10,.52,-12,gold);stroke(.5,.55,.62,.09,-12,gold)
		stroke(.48,.24,.22,.32,38,mint)
	elseif kind=="Co-op" then
		for _,x in ipairs({.3,.7}) do round(stroke(x,.34,.22,.22,0,mint));round(stroke(x,.66,.3,.26,0,gold),.4) end
		stroke(.5,.8,.66,.06,0,mint)
	elseif kind=="Hero" then
		local shield=round(stroke(.5,.48,.54,.6,0,mint),.3)
		stroke(.5,.66,.38,.38,45,mint)
		stroke(.5,.5,.1,.5,0,gold);stroke(.5,.42,.36,.1,0,gold)
	elseif kind=="Menu" then
		-- Menu: a 3 × 3 grid of tiles, the centre one lit.
		for r=0,2 do for c=0,2 do local t=stroke(.26+c*.24,.26+r*.24,.17,.17,0,(r==1 and c==1) and gold or mint);round(t,.2) end end
	elseif kind=="Map" then
		-- Sky Chart: a floating isle with a warp spark.
		round(stroke(.5,.42,.72,.3,0,mint),.5);stroke(.5,.64,.32,.32,45,gold);round(stroke(.5,.3,.16,.16,0,ivory),.5)
	elseif kind=="Settings" then
		local cog=round(stroke(.5,.5,.5,.5,0,mint),.5);make("UIStroke",cog,{Color=deep,Thickness=2})
		for _,a in ipairs({0,45,90,135}) do stroke(.5,.5,.12,.78,a,mint) end
		round(stroke(.5,.5,.2,.2,0,gold),.5)
	elseif kind=="Hunt" then
		stroke(.5,.5,.09,.8,40,mint);stroke(.5,.5,.09,.8,-40,gold)
		stroke(.29,.74,.26,.08,-50,gold);stroke(.71,.74,.26,.08,50,mint)
		local eye=stroke(.5,.5,.22,.22,45,ivory);make("UIStroke",eye,{Color=deep,Thickness=1})
	else
		-- Journal: an open chart with a compass needle.
		stroke(.5,.52,.13,.72,35,mint);stroke(.5,.52,.13,.72,-55,gold)
		local core=stroke(.5,.52,.24,.24,45,ivory);make("UIStroke",core,{Color=deep,Thickness=1})
	end
	return frame
end
-- ViewportFrames are expensive: a per-render budget plus a pool keyed by
-- template means rebuilding a page reuses the previous page's viewports.
local function thumbnail(parent,name,size,tint,noFallback,item)
	local template,key=artTemplate(name,tint)
	local itemBudget,_,decorBudget=THUMBS.limits()
	local spent=if item then thumbnailCount>=itemBudget else THUMBS.decorUsed>=decorBudget
	if not template or spent then
		if noFallback then return nil end
		return motif(parent,"Journal",size)
	end
	if item then thumbnailCount+=1 else THUMBS.decorUsed+=1 end
	local bucket=viewPool[key]
	local view=bucket and table.remove(bucket)
	if view then
		pooledViews-=1
		view.Position=UDim2.new()
		view.AnchorPoint=Vector2.zero
		view.BackgroundTransparency=0
		local frameRim=view:FindFirstChild("Rim")
		if frameRim then frameRim.Enabled=true end
		view.Size=UDim2.fromOffset(size,size)
		view.Visible=true
		view.Parent=parent
	else
		view=make("ViewportFrame",parent,{Size=UDim2.fromOffset(size,size),BackgroundColor3=rgb("10222C"),BorderSizePixel=0,Ambient=rgb("B5D8DD"),LightColor=rgb("FFE1A6"),LightDirection=Vector3.new(-1,-1,-2)})
		make("UICorner",view,{CornerRadius=UDim.new(0,10)})
		make("UIStroke",view,{Name="Rim",Color=UI.line,Thickness=1,Transparency=0})
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
	frame.BackgroundTransparency=locked and 0 or 1
	make("UICorner",frame,{CornerRadius=UDim.new(0,10)})
	local color=locked and slate or safeColor(def and def.color,mint)
	local gem=make("Frame",frame,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(.54,.54),Rotation=45,BackgroundColor3=color,BorderSizePixel=0})
	make("UICorner",gem,{CornerRadius=UDim.new(0,math.max(2,size//10))})
	make("UIGradient",gem,{Color=ColorSequence.new(Color3.new(1,1,1),rgb("6A8A93")),Rotation=90})
	make("UIStroke",gem,{Color=locked and UI.line or UI.white,Thickness=1,Transparency=locked and 0 or .55})
	local caption=label(frame,locked and "?" or initials(def and def.name or "?"),0,0,full,size,UI.heavy,locked and math.floor(size*.42) or math.max(9,math.floor(size*.27)),locked and muted or ivory)
	caption.Size=UDim2.fromScale(1,1)
	caption.TextXAlignment=Enum.TextXAlignment.Center
	caption.TextYAlignment=Enum.TextYAlignment.Center
	caption.TextStrokeTransparency=.3
	caption.TextStrokeColor3=deep
	return frame
end
-- Item icon on a rarity plate: dark-to-rarity gradient, rarity rim, and a soft
-- outer glow from Rare upwards. locked shows a sealed "?" (undiscovered).
local function itemIcon(parent,id,size,locked)
	local def=itemDef(id)
	local rarity=def and def.rarity or "Common"
	local tone=locked and slate or rgb(rarityHex(rarity))
	local holder=make("Frame",parent,{Name="ItemIcon",BackgroundColor3=tone,BackgroundTransparency=0,Size=UDim2.fromOffset(size,size),BorderSizePixel=0})
	make("UICorner",holder,{CornerRadius=UDim.new(0,10)})
	make("UIGradient",holder,{Name="Plate",Rotation=90,Color=ColorSequence.new(Color3.new(.09,.11,.13),Color3.new(.34,.34,.34))})
	if not locked and rarityRank(rarity)>=3 then
		local glow=make("Frame",holder,{Name="Glow",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.new(1,6,1,6),BackgroundColor3=tone,BackgroundTransparency=.8,BorderSizePixel=0,ZIndex=holder.ZIndex})
		make("UICorner",glow,{CornerRadius=UDim.new(0,13)})
	end
	local art
	local tinted=tintIndex()~=nil and def~=nil and type(def.color)=="string"
	if not locked and def then
		local shape=shapeFor(id,def)
		if shape then art=thumbnail(holder,shape,size,tinted and def.color or nil,true,true) end
	end
	if not art then
		itemGlyph(holder,def or {name=tostring(id)},size,locked)
	else
		art.BackgroundTransparency=1
		local frameRim=art:FindFirstChild("Rim")
		if frameRim then frameRim.Enabled=false end
		if not tinted and def and type(def.color)=="string" then
			local dot=make("Frame",holder,{Name="Swatch",Position=UDim2.new(0,5,1,-11),Size=UDim2.fromOffset(6,6),BackgroundColor3=safeColor(def.color,mint),BorderSizePixel=0})
			make("UICorner",dot,{CornerRadius=UDim.new(1,0)})
			make("UIStroke",dot,{Color=deep,Thickness=1,Transparency=.2})
		end
	end
	local rim=make("UIStroke",holder,{Name="Rarity",Color=locked and UI.line or tone,Thickness=locked and 1 or 1.5,Transparency=locked and 0 or .05})
	if not locked then make("UIGradient",rim,{Rotation=90,Color=ColorSequence.new(UI.white,Color3.new(.6,.6,.6))}) end
	return holder
end

------------------------------------------------------------------------------
-- HUD: the isle sidebar (top-right scoreboard + dock), the action bar above
-- the hotbar gap, level-up banner and toasts. XP drops and the skill toast
-- live in hud.client.lua (fed through IsleXpLocal). Lanes: UI.lay().
------------------------------------------------------------------------------
-- Sidebar: date / season / time, region, purse and Skymarks, the active
-- objective, the crew, and a dock (Menu = atlas, Bag = satchel, Map = Sky Chart).
local hud = UI.T.frame(gui, {name="Sidebar", title="AETHER  ISLES", titleAlign=Enum.TextXAlignment.Center, size=UDim2.fromOffset(214, 226), transparency=.12, header=26})
UI.gui = gui
UI.side = {}
do
	local body = hud:FindFirstChild("Body")
	local function line(name, y, color, size, font)
		local l = label(body, "", 12, y, UDim.new(1, -24), 16, font or bold, size or 13, color or ivory)
		l.Name = name
		l.RichText = true
		return l
	end
	UI.side.date = line("Date", 4, ivory, 13)
	UI.side.clock = line("Clock", 20, muted, 13)
	UI.side.region = line("Region", 36, mint, 13)
	UI.side.rule1 = UI.T.rule(body, 57, UI.brass, 10)
	UI.purse = line("Purse", 62, ivory, 13)
	UI.side.marks = line("Marks", 78, ivory, 13)
	UI.side.rule2 = UI.T.rule(body, 99, UI.brass, 10)
	UI.side.goalHead = line("GoalHead", 102, muted, 10, UI.display)
	UI.side.goalHead.Text = "OBJECTIVE"
	UI.goal = line("Goal", 115, rgb("FFE6A6"), 12)
	UI.side.crew = line("Crew", 133, muted, 12)
	UI.side.dock = make("Frame", body, {Name = "Dock", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -8), Size = UDim2.new(1, -16, 0, 36)})
	local function dockButton(name, caption, key, motifName, fn)
		local b = button(UI.side.dock, caption, UDim2.new(), UDim2.fromOffset(60, 36), fn)
		b.Name = name
		b.Text = ""
		local rim = b:FindFirstChild("Rim")
		if rim then rim.Color = UI.brass end
		local glyph = motif(b, motifName, 18)
		glyph.Name = "DockGlyph"
		glyph.AnchorPoint = Vector2.new(.5, 0)
		glyph.Position = UDim2.new(.5, 0, 0, 3)
		glyph.BackgroundTransparency = 1
		glyph:FindFirstChild("Rim").Enabled = false
		local cap = label(b, caption, 0, 0, full, 12, UI.display, 8, ivory)
		cap.Name = "DockCaption"
		cap.AnchorPoint = Vector2.new(0, 1)
		cap.Position = UDim2.new(0, 0, 1, -3)
		cap.TextXAlignment = Enum.TextXAlignment.Center
		if not Input.TouchEnabled then
			local hint = make("TextLabel", b, {Name="KeyHint", AnchorPoint=Vector2.new(1, 0), Position=UDim2.new(1, 4, 0, -4), Size=UDim2.fromOffset(14, 14),
				BackgroundColor3=gold, Text=key, Font=UI.heavy, TextSize=10, TextColor3=UI.onGold, BorderSizePixel=0})
			make("UICorner", hint, {CornerRadius=UDim.new(0, 3)})
		end
		return b
	end
	UI.side.menu = dockButton("AtlasButton", "MENU", "J", "Journal", function() UI.openAtlas() end)
	UI.side.bag = dockButton("SatchelButton", "BAG", "E", "Satchel", function() UI.hudChannel:Fire("satchel") end)
	UI.side.map = dockButton("ChartButton", "MAP", "M", "Hunt", function() UI.hudChannel:Fire("warpmap") end)
end
-- Places the sidebar and its dock for the current screen.
function UI.layoutSidebar()
	local L = UI.lay()
	local r = L.sidebar
	hud.Position, hud.Size = UDim2.fromOffset(r.x, r.y), UDim2.fromOffset(r.w, r.h)
	local short, tiny = L.short, L.tiny
	local s = UI.side
	local dockH = (short or Input.TouchEnabled) and UI.TOUCH or 36
	s.dock.Size = UDim2.new(1, -16, 0, dockH)
	local bw = math.floor((r.w - 16 - 8) / 3)
	for i, b in ipairs({s.menu, s.bag, s.map}) do
		b.Position, b.Size = UDim2.fromOffset((i - 1) * (bw + 4), 0), UDim2.fromOffset(bw, dockH)
	end
	local fs = short and 11 or 13
	for _, l in ipairs({s.date, s.clock, s.region, UI.purse, s.marks}) do l.TextSize = fs end
	-- Header band: 26 px (desktop), 18 px on phones with a smaller pixel title.
	local headerH = short and 18 or 26
	local band, body = hud:FindFirstChild("Header"), hud:FindFirstChild("Body")
	band.Size = UDim2.new(1, -6, 0, headerH - 3)
	band:FindFirstChild("Title").TextSize = short and 9 or 12
	hud:FindFirstChild("HeaderRule").Position = UDim2.new(0, 10, 0, headerH)
	body.Position, body.Size = UDim2.fromOffset(0, headerH), UDim2.new(1, 0, 1, -headerH)
	s.dock.Position = UDim2.new(0, 8, 1, short and -4 or -8)
	if short then
		-- Compact: date · time on one line, purse · marks on one line, goal last.
		s.date.Position, s.region.Position, UI.purse.Position = UDim2.fromOffset(10, 1), UDim2.fromOffset(10, 15), UDim2.fromOffset(10, 29)
		for _, l in ipairs({s.date, s.region, UI.purse}) do l.Size = UDim2.new(1, -20, 0, 14) end
		s.clock.Visible, s.marks.Visible, s.rule1.Visible, s.rule2.Visible, s.goalHead.Visible, s.crew.Visible = false, false, false, false, false, false
		UI.goal.Visible = not tiny
		UI.goal.Position, UI.goal.Size, UI.goal.TextSize, UI.goal.TextWrapped = UDim2.fromOffset(10, 44), UDim2.new(1, -20, 0, 28), 11, true
	else
		s.clock.Visible, s.marks.Visible, s.rule1.Visible, s.rule2.Visible, s.goalHead.Visible, s.crew.Visible, UI.goal.Visible = true, true, true, true, true, true, true
		s.date.Position, s.region.Position, UI.purse.Position = UDim2.fromOffset(12, 4), UDim2.fromOffset(12, 36), UDim2.fromOffset(12, 62)
		UI.goal.Position, UI.goal.Size, UI.goal.TextSize, UI.goal.TextWrapped = UDim2.fromOffset(12, 115), UDim2.new(1, -24, 0, 16), 12, false
	end
end
local openAtlas
-- Action bar (SkyBlock-style readout) over the hotbar gap: health, defense,
-- mana. Health and mana are meters with their numbers on them.
local actionBar=make("Frame",gui,{Name="ActionBar",BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.fromOffset(500,30)})
function UI.pill(parent,name,position,size)
	local pill=make("Frame",parent,{Name=name,Position=position,Size=size,BackgroundColor3=track,BackgroundTransparency=.3,BorderSizePixel=0})
	rounded(pill,5,UI.brassDark)
	return pill
end
-- Round glyph chip (frame + label so the gradient never tints the glyph).
function UI.chip(parent,glyph,color,size,x)
	local chip=make("Frame",parent,{Name="Chip",AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,x or 4,.5,0),Size=UDim2.fromOffset(size,size),BackgroundColor3=color,BorderSizePixel=0})
	make("UICorner",chip,{CornerRadius=UDim.new(1,0)})
	make("UIGradient",chip,{Rotation=90,Color=ColorSequence.new(UI.white,Color3.new(.5,.5,.5))})
	make("UIStroke",chip,{Color=UI.white,Thickness=1,Transparency=.6})
	local text=make("TextLabel",chip,{Name="Glyph",BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Text=glyph,Font=UI.heavy,TextSize=math.floor(size*.62),TextColor3=UI.white,TextStrokeTransparency=.5,TextStrokeColor3=deep})
	return chip,text
end
-- A gradient meter with gloss (HUD and atlas share it).
function UI.meter(parent,name,color,height)
	local bar=make("Frame",parent,{Name=name,BackgroundColor3=track,BorderSizePixel=0,Size=UDim2.new(1,0,0,height)})
	make("UICorner",bar,{CornerRadius=UDim.new(0,math.min(4,height//2))})
	make("UIStroke",bar,{Color=UI.brassDark,Transparency=0,Thickness=1})
	local fill=make("Frame",bar,{Name="Fill",BackgroundColor3=color,BorderSizePixel=0,Size=UDim2.fromScale(1,1)})
	make("UICorner",fill,{CornerRadius=UDim.new(0,math.min(4,height//2))})
	make("UIGradient",fill,{Name="Shade",Rotation=90,Color=ColorSequence.new(UI.white,Color3.new(.62,.62,.62))})
	local gloss=make("Frame",fill,{Name="Gloss",BackgroundColor3=UI.white,BackgroundTransparency=.8,BorderSizePixel=0,Position=UDim2.fromOffset(1,1),Size=UDim2.new(1,-2,.38,0)})
	make("UICorner",gloss,{CornerRadius=UDim.new(0,math.min(3,height//2))})
	local cap=make("Frame",fill,{Name="Cap",AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-1,.5,0),Size=UDim2.fromOffset(2,math.max(2,height-4)),BackgroundColor3=color:Lerp(UI.white,.65),BorderSizePixel=0})
	return bar,fill,cap
end
function UI.setMeter(fill,fraction)
	fraction=math.clamp(num(fraction,0),0,1)
	fill.Size=UDim2.fromScale(fraction,1)
	fill.Visible=fraction>0
	local cap=fill:FindFirstChild("Cap")
	if cap then cap.Visible=fraction>.04 and fraction<.995 end
end
do
	local function readout(parent,name)
		local t=label(parent,"—",0,0,full,16,UI.heavy,13,ivory)
		t.Name=name
		t.Size=UDim2.fromScale(1,1)
		t.TextXAlignment=Enum.TextXAlignment.Center
		t.TextStrokeTransparency=.2
		t.TextStrokeColor3=track
		t.ZIndex=2
		t.RichText=true
		return t
	end
	local health=UI.pill(actionBar,"HealthPill",UDim2.new(),UDim2.new(.38,-4,1,0))
	local meter
	meter,UI.healthFill=UI.meter(health,"HealthMeter",UI.T.color.health,16)
	meter.Position,meter.Size=UDim2.fromOffset(3,3),UDim2.new(1,-6,1,-6)
	UI.healthText=readout(meter,"HealthText")
	local defense=UI.pill(actionBar,"DefensePill",UDim2.new(.38,2,0,0),UDim2.new(.24,-4,1,0))
	UI.defenseText=readout(defense,"DefenseText")
	UI.defenseText.TextColor3=rgb("8CF59A")
	local manaPill=UI.pill(actionBar,"ManaPill",UDim2.new(.62,4,0,0),UDim2.new(.38,-4,1,0))
	local manaMeter
	manaMeter,UI.manaFill=UI.meter(manaPill,"ManaMeter",UI.T.color.mana,16)
	manaMeter.Position,manaMeter.Size=UDim2.fromOffset(3,3),UDim2.new(1,-6,1,-6)
	UI.manaText=readout(manaMeter,"ManaText")
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() UI.layoutSidebar();UI.layoutActionBar() end)
-- The island builder owns the bottom of the screen (the hotbar hides too).
player:GetAttributeChangedSignal("IslandBuilding"):Connect(function() UI.layoutActionBar() end)
-- The Wayfinder publishes the region under the player (sidebar region line).
player:GetAttributeChangedSignal("IsleRegionHere"):Connect(function() if UI.refreshSidebar then UI.refreshSidebar() end end)
-- §33: the pinned quest-helper step (server attribute) refreshes the Objective line at once.
player:GetAttributeChangedSignal("IsleObjectivePin"):Connect(function() if UI.refreshSidebar then UI.refreshSidebar() end end)
function UI.layoutActionBar()
	local L=UI.lay()
	actionBar.Position,actionBar.Size=UDim2.fromOffset(L.action.x,L.action.y),UDim2.fromOffset(L.action.w,L.action.h)
	actionBar.Visible=not (UI.atlasOpen==true) and player:GetAttribute("IslandBuilding")~=true
	local size=L.tiny and 11 or (L.short and 12 or 13)
	for _,t in ipairs({UI.healthText,UI.defenseText,UI.manaText}) do t.TextSize=size end
end
-- Level-up banner sits below the top HUD row: the combat target panel and its
-- banner own y 10-138 (combat.client.lua), the atlas HUD the top-left corner.
do
	local banner=panel(gui,UDim2.new(.5,0,0,142),UDim2.new(.9,0,0,82),deep)
	banner.Name="LevelBanner"
	banner.AnchorPoint=Vector2.new(.5,0)
	banner.Visible=false
	banner.ZIndex=5
	banner.BackgroundTransparency=.04
	make("UISizeConstraint",banner,{Name="BannerLimit",MaxSize=Vector2.new(440,82)})
	rounded(banner,14,gold)
	UI.sheen(banner,1,.68)
	UI.bevel(banner,14,.72)
	UI.corners(banner,gold,6,7)
	UI.bannerScale=make("UIScale",banner,{Scale=1})
	for _,x in ipairs({0,1}) do
		local wing=make("Frame",banner,{Name="RibbonEnd",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,(x==0 and -1 or 1)*66,0,1),Size=UDim2.fromOffset(16,16),Rotation=45,BackgroundColor3=UI.brass,BorderSizePixel=0})
		make("UIStroke",wing,{Color=UI.brassDark,Thickness=1})
	end
	local ribbon=make("Frame",banner,{Name="Ribbon",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,0,0,1),Size=UDim2.fromOffset(128,22),BackgroundColor3=gold,BorderSizePixel=0})
	make("UICorner",ribbon,{CornerRadius=UDim.new(0,6)})
	make("UIStroke",ribbon,{Color=UI.brassDark,Thickness=1})
	UI.sheen(ribbon,1,.78)
	local kicker=label(ribbon,"LEVEL  UP",0,0,full,22,UI.heavy,12,UI.onGold)
	kicker.TextXAlignment=Enum.TextXAlignment.Center
	local emblem=make("Frame",banner,{Name="Emblem",AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,16,.5,5),Size=UDim2.fromOffset(48,48),BackgroundColor3=mint,BorderSizePixel=0})
	make("UICorner",emblem,{CornerRadius=UDim.new(1,0)})
	make("UIGradient",emblem,{Rotation=90,Color=ColorSequence.new(UI.white,Color3.new(.45,.45,.45))})
	local ring=make("UIStroke",emblem,{Color=gold,Thickness=2})
	make("UIGradient",ring,{Rotation=90,Color=ColorSequence.new(UI.white,Color3.new(.55,.55,.55))})
	UI.bannerInitial=label(emblem,"",0,0,full,48,book,20,UI.white)
	UI.bannerInitial.Size=UDim2.fromScale(1,1)
	UI.bannerInitial.TextXAlignment=Enum.TextXAlignment.Center
	UI.bannerInitial.TextStrokeTransparency=.3
	UI.bannerInitial.TextStrokeColor3=deep
	UI.bannerTitle=label(banner,"",76,17,UDim.new(1,-92),32,book,16,ivory)
	UI.bannerReward=label(banner,"",76,50,UDim.new(1,-92),20,bold,12,muted)
	UI.bannerReward.RichText=true
	UI.bannerReward.TextScaled=true
	make("UITextSizeConstraint",UI.bannerReward,{MinTextSize=11,MaxTextSize=13})
	UI.banner,UI.bannerEmblem=banner,emblem
end

------------------------------------------------------------------------------
-- The atlas window: shade, drop shadow, brass double rim with ornamental
-- corners, masthead, tab strip, page scroller and footer.
------------------------------------------------------------------------------
local shade = make("TextButton", gui, {
	Name = "Shade",
	Text = "",
	AutoButtonColor = false,
	BackgroundColor3 = track,
	BackgroundTransparency = 0.35,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	Selectable = false,
})
make("UIGradient", shade, {Rotation=90, Transparency=NumberSequence.new(.3, 0)})
local atlas = make("Frame", gui, {Name="Atlas", Active=true, AnchorPoint=Vector2.new(.5, .5), Position=UDim2.fromScale(.5, .5),
	Size=UDim2.new(1, -20, 1, -20), BackgroundTransparency=1, Visible=false})
make("UISizeConstraint", atlas, { MaxSize = Vector2.new(860, 700) })
UI.atlasScale = make("UIScale", atlas, {Scale=1})
for _, spec in ipairs({{3, 5, .6, 18}, {9, 11, .84, 24}}) do
	local shadow = make("Frame", atlas, {Name="Shadow", AnchorPoint=Vector2.new(.5, .5), Position=UDim2.new(.5, 0, .5, spec[2]), Size=UDim2.new(1, spec[1]*2, 1, spec[1]*2),
		BackgroundColor3=UI.black, BackgroundTransparency=spec[3], BorderSizePixel=0})
	make("UICorner", shadow, {CornerRadius=UDim.new(0, spec[4])})
end
do
	local window = panel(atlas, UDim2.new(), UDim2.fromScale(1, 1), ink)
	window.Name = "Window"
	make("UICorner", window, {CornerRadius=UDim.new(0, 16)})
	UI.T.rim(window, 2.5)
	make("UIGradient", window, {Name="Sheen", Rotation=90, Color=ColorSequence.new(rgb("E4E9F0"), rgb("8A93A0"))})
	local inner = make("Frame", window, {Name="InnerRim", BackgroundTransparency=1, Position=UDim2.fromOffset(5, 5), Size=UDim2.new(1, -10, 1, -10)})
	make("UICorner", inner, {CornerRadius=UDim.new(0, 12)})
	make("UIStroke", inner, {Color=UI.T.color.frameHi, Transparency=.78, Thickness=1})
	UI.corners(window, UI.T.color.frameHi, 7, 6)
end
UI.head = make("Frame", atlas, {Name="Head", BackgroundTransparency=1, Size=UDim2.new(1, 0, 0, 70)})
do
	local wash = make("Frame", UI.head, {Name="Wash", BackgroundColor3=UI.raised, BackgroundTransparency=.3, Size=UDim2.fromScale(1, 1), BorderSizePixel=0})
	make("UICorner", wash, {CornerRadius=UDim.new(0, 16)})
	make("UIGradient", wash, {Rotation=90, Transparency=NumberSequence.new(.15, 1)})
end
UI.crest = UI.compass(UI.head, 16, 13, 44)
UI.kicker = label(UI.head, "CARTOGRAPHERS' GUILD", 70, 12, UDim.new(1, -250), 14, UI.heavy, 11, mint)
UI.title = label(UI.head, "Voyager’s Atlas", 69, 25, UDim.new(1, -250), 36, book, 18, ivory)
make("UIGradient", UI.title, {Rotation=90, Color=ColorSequence.new(rgb("FFF7E2"), rgb("F2C15E"))})
UI.headRule = UI.rule(UI.head, UI.brass, 69, 14)
-- Purse chip in the masthead.
UI.coins = make("Frame", UI.head, {Name="Purse", AnchorPoint=Vector2.new(1, .5), Position=UDim2.new(1, -66, .5, 0), Size=UDim2.fromOffset(128, 32), BackgroundColor3=track, BackgroundTransparency=.2, BorderSizePixel=0})
rounded(UI.coins, 16, UI.brass)
do
	local coin = UI.chip(UI.coins, "", gold, 20, 6)
	local inner = make("Frame", coin, {AnchorPoint=Vector2.new(.5, .5), Position=UDim2.fromScale(.5, .5), Size=UDim2.fromScale(.55, .55), BackgroundTransparency=1})
	make("UICorner", inner, {CornerRadius=UDim.new(1, 0)})
	make("UIStroke", inner, {Color=UI.brassDark, Thickness=1.5})
	UI.coinText = label(UI.coins, "—", 30, 0, UDim.new(1, -40), 32, UI.heavy, 14, ivory)
	UI.coinText.TextXAlignment = Enum.TextXAlignment.Right
end
local function closeAtlas()
	atlas.Visible = false
	shade.Visible = false
	hud.Visible = true
	UI.atlasOpen = false
	UI.layoutActionBar()
	-- Leave UI selection entirely so gamepad input drives the character again.
	GuiService.SelectedObject = nil
end
UI.close = button(UI.head, "Close", UDim2.new(1, -54, 0, 15), UDim2.fromOffset(40, 40), closeAtlas)
UI.close.Text = "✕"
UI.close.TextSize = 18
shade.Activated:Connect(closeAtlas)
local tabs = make("Frame", atlas, {Name="Tabs", BackgroundTransparency=1, Position=UDim2.fromOffset(12, 76), Size=UDim2.new(1, -24, 0, 60)})
local scroll = make("ScrollingFrame", atlas, {
	Name = "Pages",
	Position = UDim2.fromOffset(14, 146),
	Size = UDim2.new(1, -28, 1, -180),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = UI.brass,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
})
make("UIListLayout", scroll, { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) })
make("UIPadding", scroll, {PaddingTop=UDim.new(0, 2), PaddingBottom=UDim.new(0, 10), PaddingLeft=UDim.new(0, 1)})
UI.footRule = UI.rule(atlas, UI.brass, 0, 16)
UI.footRule.Position = UDim2.new(0, 16, 1, -31)
UI.footer = label(atlas, "", 18, 0, UDim.new(1, -36), 22, UI.heavy, 11, gold)
UI.footer.Position = UDim2.new(0, 18, 1, -28)
UI.hint = label(atlas, "", 18, 0, UDim.new(1, -36), 22, UI.heavy, 11, muted)
UI.hint.Position = UDim2.new(0, 18, 1, -28)
UI.hint.TextXAlignment = Enum.TextXAlignment.Right
-- Toast: one strip above the action bar with a gold accent edge.
local notice = label(gui, "", 0, 0, UDim.new(0.92, 0), 38, bold, 14, ivory)
notice.Name = "Toast"
notice.AnchorPoint = Vector2.new(0.5, 1)
notice.Position = UDim2.new(0.5, 0, 1, -50)
notice.TextXAlignment = Enum.TextXAlignment.Center
notice.TextWrapped = true
notice.BackgroundColor3 = deep
notice.BackgroundTransparency = 0.05
notice.Visible = false
rounded(notice, 12, UI.brass)
notice.AutomaticSize = Enum.AutomaticSize.Y
notice.TextTruncate = Enum.TextTruncate.None
make("UIPadding", notice, {PaddingTop=UDim.new(0,9),PaddingBottom=UDim.new(0,9),PaddingLeft=UDim.new(0,18),PaddingRight=UDim.new(0,14)})
make("UISizeConstraint", notice, { Name = "NoticeLimit", MaxSize = Vector2.new(560, 180) })
do
	local accent = make("Frame", notice, {Name="Accent", Position=UDim2.new(0, -11, 0, -2), Size=UDim2.new(0, 3, 1, 4), BackgroundColor3=gold, BorderSizePixel=0})
	make("UICorner", accent, {CornerRadius=UDim.new(1, 0)})
end
UI.noticeIndex = 0
local function notify(message)
	if type(message)~="string" or message == "" then
		return
	end
	-- Phones (compact layout): one short strip that stays clear of touch controls.
	local compactToast = THUMBS.compact
	notice:FindFirstChild("NoticeLimit").MaxSize = compactToast and Vector2.new(340, 60) or Vector2.new(560, 180)
	notice.TextSize = compactToast and 12 or 14
	notice.TextTruncate = compactToast and Enum.TextTruncate.AtEnd or Enum.TextTruncate.None
	UI.noticeIndex += 1
	local token = UI.noticeIndex
	notice.Text = message
	notice.Visible = true
	notice.TextTransparency = 0.35
	-- The combat spell bar (combat.client.lua) publishes its height as IsleHudLift.
	-- Above the hotbar band (UI.lay().toastBottom) and any spell / prayer bars.
	local lift = math.max(UI.lay().toastBottom, 50 + math.clamp(num(player:GetAttribute("IsleHudLift"),0),0,200))
	notice.Position = UDim2.new(0.5, 0, 1, 8 - lift)
	TweenService:Create(notice, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0, Position = UDim2.new(0.5, 0, 1, -lift) }):Play()
	task.delay(3.6, function()
		if token == UI.noticeIndex then
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
local current = "Menu"
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
-- Sidebar text (snapshot + 1 Hz clock). Strings only; no instances made.
-- §31 MMO Features: the Isle Renown level on the sidebar and the server-driven
-- Wayfarer's Path step in the Objective slot (legacy nextGoal() once it is done).
function UI.renownTag(gap)
	local r = type(state) == "table" and type(state.renown) == "table" and state.renown
	if not r or type(r.level) ~= "number" then return "" end
	local hex = type(r.color) == "string" and #r.color == 6 and r.color or "FFFFFF"
	return gap .. paint("✪ " .. fmt(r.level), hex)
end
-- Shop quantity picker (features.client.lua listens on IsleQuantityLocal).
function UI.pickQuantity(spec)
	local event = ReplicatedStorage:FindFirstChild("IsleQuantityLocal")
	if not event then
		event = Instance.new("BindableEvent")
		event.Name = "IsleQuantityLocal"
		event.Parent = ReplicatedStorage
	end
	UI.lastQuantity = spec
	event:Fire(spec)
end
-- Lots of a cost {coins=, item=n} the purse and satchel cover (1..64).
function UI.affordLots(cost)
	local most = Data and Data.Features and Data.Features.Shop.MAX_LOTS or 64
	for id, n in pairs(tbl(cost)) do
		if type(n) == "number" and n > 0 then
			local have = if id == "coins" then num(state.coins, 0) else num(tbl(state.items)[id], 0)
			most = math.min(most, math.floor(have / n))
		end
	end
	return math.max(1, most)
end
function UI.objective()
	-- §33: a pinned quest-helper step (server attribute IsleObjectivePin) comes first.
	local pin = player:GetAttribute("IsleObjectivePin")
	if type(pin) == "string" and pin ~= "" then
		local sp = type(state.systems) == "table" and type(state.systems.pin) == "table" and state.systems.pin
		-- §33 QC L8: the guide's position is labelled ("step 2/4") so it never reads as a second count.
		return escape(pin) .. (sp and type(sp.step) == "number" and paint("  · step " .. sp.step .. "/" .. tostring(sp.total or sp.step), "A9B4C0") or "")
	end
	local g = type(state.guide) == "table" and state.guide
	if g and not g.complete and type(g.title) == "string" then
		return g.title .. paint("  " .. tostring(g.step or 1) .. "/" .. tostring(g.total or 10), "A9B4C0")
	end
	if g and type(g.owed) == "number" and g.owed > 0 then return "Claim your Path rewards (Menu › Renown)" end
	return UI.nextGoal()
end
function UI.refreshSidebar()
	local s = UI.side
	local L = UI.lay()
	local now = os.time()
	local ok, server = pcall(function() return workspace:GetServerTimeNow() end)
	if ok and type(server) == "number" and server > 1e9 then now = server end
	local cal = UI.T.isleClock(now, Data)
	if cal then
		local sun = cal.night and paint("☾", "B8C0FF") or paint("☀", "F7C548")
		if L.short then
			s.date.Text = paint(cal.seasonName .. " " .. cal.day, cal.seasonColor) .. paint(" · " .. cal.clock, "A9B4C0")
		else
			s.date.Text = paint(cal.date, cal.seasonColor) .. paint("   Year " .. cal.year, "6E7A88")
			s.clock.Text = cal.clock .. "  " .. sun .. (cal.event and paint("   ✦ event", "F7C548") or "")
		end
	else
		s.date.Text, s.clock.Text = "Skyward Calendar", ""
	end
	local here = player:GetAttribute("IsleRegionHere")
	local region = type(here) == "string" and Data and type(Data.RegionById) == "table" and Data.RegionById[here]
	s.region.Text = "◉ " .. escape(region and region.name or (here == "Home" and "Your Isle") or (type(here) == "string" and here ~= "" and here) or "The Skyways")
	local coins = fmt(num(state.coins, 0))
	local marks = fmt(num(tbl(state.items).Skymark, 0))
	if L.short then
		UI.purse.Text = synced and (paint("◆ " .. coins, "F7C548") .. paint("   ✦ " .. marks, "55FFFF") .. UI.renownTag("   ")) or "Opening ledger…"
	else
		UI.purse.Text = synced and ("Purse: " .. paint(coins, "F7C548")) or "Opening ledger…"
		s.marks.Text = "Skymarks: " .. paint(marks, "55FFFF") .. UI.renownTag("   ")
	end
	local crew = coopState and type(coopState.members) == "table" and #coopState.members or 0
	s.crew.Text = crew > 0 and ("Crew: " .. paint(crew .. " member" .. (crew == 1 and "" or "s"), "6FE3C8")) or ("Crew: " .. paint("solo", "6E7A88") .. (state.ironman and paint("  ·  Ironman", "A9B4C0") or ""))
end
local function listItem(object)
	order += 1
	object.LayoutOrder = order
	return object
end
-- Section divider: gold diamond, heading in caps, optional meta copy on the
-- right ("TITLE    /    META") and a brass hairline that fades to the right.
-- A leading number ("01    /    NEXT BEARING") becomes a numbered medallion.
local function heading(text)
	local h=compactAtlas and 26 or 30
	local strip=listItem(make("Frame",scroll,{Name="Heading",BackgroundTransparency=1,Size=UDim2.new(1,-7,0,h)}))
	local main,meta=tostring(text):match("^(.-)%s+/%s+(.+)$")
	main=main or tostring(text)
	local x=2
	if main:match("^%d+$") and meta then
		local medal=make("TextLabel",strip,{Name="Number",AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,2,.5,-2),Size=UDim2.fromOffset(24,18),BackgroundColor3=gold,
			Text=main,Font=UI.heavy,TextSize=11,TextColor3=UI.onGold,BorderSizePixel=0})
		make("UICorner",medal,{CornerRadius=UDim.new(0,5)})
		main,meta,x=meta,nil,32
		local rest,more=main:match("^(.-)%s+/%s+(.+)$")
		if rest then main,meta=rest,more end
	else
		local gem=make("Frame",strip,{Name="Gem",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(0,7,.5,-2),Size=UDim2.fromOffset(8,8),Rotation=45,BackgroundColor3=gold,BorderSizePixel=0})
		make("UIStroke",gem,{Color=UI.brassDark,Thickness=1})
		x=20
	end
	local title=label(strip,string.upper(main),x,0,UDim.new(1,-x),h-4,UI.display,compactAtlas and 10 or 11,gold)
	title.TextStrokeTransparency=.55
	title.TextStrokeColor3=track
	if meta then
		title.Size=UDim2.new(.62,-x,0,h-4)
		local right=label(strip,meta,0,0,UDim.new(.38,0),h-4,bold,compactAtlas and 12 or 11,muted)
		right.Position=UDim2.new(.62,0,0,0)
		right.TextXAlignment=Enum.TextXAlignment.Right
	end
	local line=make("Frame",strip,{Name="Rule",BackgroundColor3=UI.brass,BorderSizePixel=0,Position=UDim2.new(0,2,1,-3),Size=UDim2.new(1,-2,0,1)})
	make("UIGradient",line,{Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(.6,.55),NumberSequenceKeypoint.new(1,1)})})
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
	return make("TextLabel",parent,{Name="Copy",Text=value,RichText=true,BackgroundTransparency=1,Font=regular,TextSize=size or (compactAtlas and 12 or 14),TextColor3=color or UI.copy,
		TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,TextWrapped=true,Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,LayoutOrder=order or 0})
end
-- Progress bar: sunken well, gradient fill with gloss and a glowing end cap.
local function progress(parent,fraction,color,caption,height)
	height=height or (compactAtlas and 16 or 18)
	local bar,fill=UI.meter(parent,"Progress",color or mint,height)
	UI.setMeter(fill,fraction)
	if caption then
		local text=label(bar,caption,0,0,full,height,UI.heavy,math.max(9,height-6),ivory)
		text.Size=UDim2.fromScale(1,1)
		text.TextXAlignment=Enum.TextXAlignment.Center
		text.TextStrokeTransparency=.25
		text.TextStrokeColor3=deep
	end
	return bar
end
-- Tier pips: filled segments glow in the line colour; the next one is outlined.
local function pips(parent,total,filled,color,labels)
	local strip=make("Frame",parent,{Name="Pips",BackgroundTransparency=1,Size=UDim2.new(1,0,0,compactAtlas and 18 or 20)})
	for i=1,total do
		local reached=i<=filled
		local pip=make("Frame",strip,{Position=UDim2.new((i-1)/total,1,0,0),Size=UDim2.new(1/total,-4,1,0),BackgroundColor3=reached and (color or gold) or track,BorderSizePixel=0})
		make("UICorner",pip,{CornerRadius=UDim.new(0,5)})
		if reached then UI.sheen(pip,1,.62)
		else make("UIStroke",pip,{Color=i==filled+1 and (color or gold) or UI.line,Transparency=i==filled+1 and .2 or 0,Thickness=1}) end
		if labels and labels[i] then
			local text=label(pip,labels[i],0,0,full,compactAtlas and 18 or 20,UI.heavy,11,reached and deep or muted)
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
	make("UIGridLayout",holder,{CellSize=cell,CellPadding=UDim2.fromOffset(padding or 8,padding or 8),SortOrder=Enum.SortOrder.LayoutOrder})
	make("UIPadding",holder,{PaddingTop=UDim.new(0,3),PaddingBottom=UDim.new(0,3),PaddingLeft=UDim.new(0,3)})
	return holder
end
-- Tile: raised plate for grids (items, skills, slots); callers add a rim.
local function tile(parent,name,layoutOrder,action)
	local b=make("TextButton",parent,{Name=name,Text="",AutoButtonColor=false,BackgroundColor3=rgb("10202A"),BorderSizePixel=0,Selectable=true,LayoutOrder=layoutOrder or 0,ClipsDescendants=true})
	make("UICorner",b,{CornerRadius=UDim.new(0,12)})
	UI.sheen(b,1,.7)
	pressable(b)
	b.Activated:Connect(action)
	return b
end
local function contentWidth()
	local width=scroll.AbsoluteSize.X
	if type(width)~="number" or width<=0 then width=compactAtlas and 420 or 700 end
	return width-7
end
-- Pill badge (status chip) right-aligned at y in a band.
function UI.badge(parent,text,color,y)
	local chip=make("TextLabel",parent,{Name="Badge",Text=text,RichText=true,AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,0,0,y),Size=UDim2.fromOffset(0,22),
		AutomaticSize=Enum.AutomaticSize.X,BackgroundColor3=color,BackgroundTransparency=.84,Font=UI.heavy,TextSize=compactAtlas and 12 or 12,TextColor3=color,BorderSizePixel=0})
	make("UICorner",chip,{CornerRadius=UDim.new(1,0)})
	make("UIStroke",chip,{Color=color,Transparency=.45,Thickness=1})
	make("UIPadding",chip,{PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10)})
	return chip
end
-- Corner tag on a tile (e.g. "E" for equipped): a small gold plate.
function UI.tag(parent,text)
	local chip=make("TextLabel",parent,{Name="Tag",Position=UDim2.fromOffset(4,4),Size=UDim2.fromOffset(16,16),BackgroundColor3=gold,Text=text,Font=UI.heavy,TextSize=11,TextColor3=UI.onGold,BorderSizePixel=0,ZIndex=2})
	make("UICorner",chip,{CornerRadius=UDim.new(0,5)})
	make("UIStroke",chip,{Color=UI.brassDark,Thickness=1})
	return chip
end
-- Shared card: layered plate (sheen + bevel + rim), icon well, rich title and
-- subtitle, status pill, copy lines, progress bar, pips and right-aligned
-- actions (gold primary, slate secondary, sunken disabled).
function card(o)
	local box=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,0),o.fill or deep))
	box.AutomaticSize=Enum.AutomaticSize.Y
	if o.name then box.Name=o.name end
	make("UICorner",box,{CornerRadius=UDim.new(0,12)})
	local rim=make("UIStroke",box,{Color=o.edge or UI.line,Thickness=o.edge and 1.5 or 1,Transparency=0})
	make("UIGradient",rim,{Rotation=90,Color=ColorSequence.new(UI.white,Color3.new(.6,.6,.6))})
	UI.sheen(box,1,.78)
	UI.bevel(box,12,.88)
	if o.accent then
		local strip=make("Frame",box,{Name="Accent",Position=UDim2.fromOffset(0,10),Size=UDim2.new(0,3,1,-20),BackgroundColor3=o.accent,BorderSizePixel=0})
		make("UICorner",strip,{CornerRadius=UDim.new(1,0)})
		local glow=make("Frame",box,{Name="AccentGlow",Position=UDim2.fromOffset(0,6),Size=UDim2.new(0,8,1,-12),BackgroundColor3=o.accent,BackgroundTransparency=.82,BorderSizePixel=0})
		make("UICorner",glow,{CornerRadius=UDim.new(0,4)})
	end
	local body=make("Frame",box,{Name="Body",BackgroundTransparency=1,Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y})
	local pad=compactAtlas and 10 or 14
	make("UIPadding",body,{PaddingTop=UDim.new(0,pad),PaddingBottom=UDim.new(0,pad),PaddingLeft=UDim.new(0,pad+(o.accent and 4 or 0)),PaddingRight=UDim.new(0,pad)})
	make("UIListLayout",body,{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,compactAtlas and 6 or 8)})
	local index=0
	local function nextOrder() index+=1 return index end
	local iconSize=o.iconSize or (compactAtlas and 38 or 48)
	local hasIcon=o.item~=nil or o.icon~=nil or o.motif~=nil or o.locked
	local titleSize=compactAtlas and 15 or 17
	local bandHeight=hasIcon and iconSize or (o.subtitle and 40 or 22)
	local band=make("Frame",body,{Name="Band",BackgroundTransparency=1,Size=UDim2.new(1,0,0,bandHeight),LayoutOrder=nextOrder()})
	local textX=0
	if hasIcon then
		if o.item~=nil or o.locked then itemIcon(band,o.item,iconSize,o.locked)
		elseif o.icon then o.icon(band,iconSize)
		else motif(band,o.motif,iconSize) end
		textX=iconSize+12
	end
	-- Badge column grows with its copy (rich tags stripped) instead of truncating.
	local badgeWidth=0
	if o.badge then
		local plain=tostring(o.badge):gsub("<[^>]+>","")
		badgeWidth=math.clamp((utf8.len(plain) or #plain)*8+26,compactAtlas and 56 or 64,compactAtlas and 150 or 190)
	end
	local blockHeight=22+(o.subtitle and 18 or 0)
	local top=math.max(0,(bandHeight-blockHeight)//2)
	local title=label(band,o.title or "",textX,top,UDim.new(1,-textX-badgeWidth-6),22,UI.heavy,titleSize,o.titleColor or ivory)
	title.RichText=true
	if o.subtitle then
		local sub=label(band,o.subtitle,textX,top+21,UDim.new(1,-textX-badgeWidth-6),18,regular,compactAtlas and 12 or 13,o.subtitleColor or muted)
		sub.RichText=true
	end
	if o.badge then UI.badge(band,o.badge,o.badgeColor or gold,top) end
	if type(o.detail)=="string" and o.detail~="" then para(body,o.detail,nextOrder(),o.detailColor) end
	if o.before then o.before(body,nextOrder) end
	local lines=o.lines or EMPTY
	for i=1,16 do
		local line=lines[i]
		if type(line)=="string" and line~="" then para(body,line,nextOrder(),o.linesColor or muted,compactAtlas and 12 or 13) end
	end
	if o.pips then pips(body,o.pips.total,o.pips.filled,o.pips.color,o.pips.labels).LayoutOrder=nextOrder() end
	if o.bar then progress(body,o.bar.fraction,o.bar.color,o.bar.caption).LayoutOrder=nextOrder() end
	if o.after then o.after(body,nextOrder) end
	if o.actions and #o.actions>0 then
		local height=compactAtlas and UI.TOUCH or 40
		local width=compactAtlas and 104 or 124
		local strip=make("Frame",body,{Name="Actions",BackgroundTransparency=1,Size=UDim2.new(1,0,0,height),LayoutOrder=nextOrder()})
		-- Each button widens to keep its caption on one line ("Switch · 25,000"),
		-- sharing the strip with its neighbours: never narrower than the base width.
		local widths,total={},0
		local room=contentWidth()-2*(compactAtlas and 10 or 14)-8
		for i,action in ipairs(o.actions) do
			local chars=utf8.len(action.caption) or #action.caption
			widths[i]=math.max(width,math.min(compactAtlas and 190 or 220,chars*8+(chars<=7 and 46 or 28)))
			total+=widths[i]+(i>1 and 8 or 0)
		end
		if total>room then
			for i=1,#widths do widths[i]=width end
			total=#o.actions*width+(#o.actions-1)*8
		end
		local x=-total
		for i,action in ipairs(o.actions) do
			local w=widths[i]
			local b=button(strip,action.caption,UDim2.new(1,x,0,0),UDim2.fromOffset(w,height),function()
				if action.disabled then notify(action.reason or "Not available yet.") return end
				action.fn()
			end)
			b.Name=action.name or ((o.name or "Card")..(action.caption:gsub("[^%w]","")))
			b.TextScaled=true
			make("UITextSizeConstraint",b,{MinTextSize=11,MaxTextSize=14})
			if #action.caption<=7 then UI.engrave(b,action.caption) end
			local danger=action.caption=="Abandon" or action.caption=="Remove" or action.caption=="Dismantle" or action.caption=="Unequip" or action.caption=="Cancel lot"
			UI.tone(b,action.disabled and "disabled" or (action.primary and "primary") or (danger and "danger") or nil)
			x+=w+8
		end
	end
	return box
end
-- Checklist: a sunken panel of tick boxes (✓ mint / ✗ ember), task copy and a
-- right-aligned have/need count. items: {text=rich, met=bool, amount=string?}.
function UI.checklist(body,nextOrder,caption,items)
	if caption then
		local cap=para(body,caption,nextOrder(),gold,12)
		cap.Font=UI.heavy
		cap.Name="Caption"
	end
	local list=make("Frame",body,{Name="Checklist",BackgroundColor3=track,BackgroundTransparency=.45,Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,LayoutOrder=nextOrder(),BorderSizePixel=0})
	make("UICorner",list,{CornerRadius=UDim.new(0,8)})
	make("UIListLayout",list,{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,3)})
	make("UIPadding",list,{PaddingTop=UDim.new(0,6),PaddingBottom=UDim.new(0,6),PaddingLeft=UDim.new(0,8),PaddingRight=UDim.new(0,10)})
	for i,item in ipairs(items) do
		local line=make("Frame",list,{Name="Check",BackgroundTransparency=1,Size=UDim2.new(1,0,0,compactAtlas and 18 or 20),AutomaticSize=Enum.AutomaticSize.Y,LayoutOrder=i})
		local box=make("TextLabel",line,{Name="Box",Position=UDim2.fromOffset(0,2),Size=UDim2.fromOffset(16,16),BackgroundColor3=item.met and mint or track,Text=item.met and "✓" or "✗",
			Font=UI.heavy,TextSize=11,TextColor3=item.met and deep or ember,BorderSizePixel=0})
		make("UICorner",box,{CornerRadius=UDim.new(0,4)})
		if not item.met then make("UIStroke",box,{Color=UI.line,Thickness=1}) end
		local amountWidth=item.amount and 78 or 0
		local text=label(line,item.text,24,0,UDim.new(1,-24-amountWidth),compactAtlas and 18 or 20,regular,compactAtlas and 12 or 13,item.met and UI.copy or muted)
		text.RichText=true
		text.TextWrapped=true
		text.TextTruncate=Enum.TextTruncate.None
		text.AutomaticSize=Enum.AutomaticSize.Y
		if item.amount then
			local amount=label(line,item.amount,0,0,UDim.new(0,amountWidth),compactAtlas and 18 or 20,UI.heavy,compactAtlas and 12 or 13,item.met and mint or muted)
			amount.Position=UDim2.new(1,-amountWidth,0,0)
			amount.TextXAlignment=Enum.TextXAlignment.Right
		end
	end
	return list
end
-- Segmented control: a sunken well with flat segments; the chosen segment is
-- a raised gold (page sections) or mint (in-page filters) plate.
local function sectionBar(options,selected,onPick,opts)
	opts=opts or {}
	local n=#options
	if n==0 then return end
	local maxPer=opts.maxPer or ((compactAtlas and not railMode) and 3 or (compactAtlas and 6 or 7))
	local rows=math.ceil(n/maxPer)
	local per=math.ceil(n/rows)
	local height=opts.small and (compactAtlas and 30 or 32) or (compactAtlas and 34 or 38)
	local inset=4
	-- Phones: one row of UI.TOUCH-tall segments sized to their captions. When
	-- they do not all fit, the well scrolls sideways (selected segment brought
	-- into view) instead of stacking rows that push the page off a short screen.
	local strip=nil
	if compactAtlas then
		height=UI.TOUCH
		local avail=contentWidth()-inset*2
		local widths,total={},0
		for i,name in ipairs(options) do
			local text=tostring(name)
			widths[i]=math.max(64,(utf8.len(text) or #text)*8+28)
			total+=widths[i]+(i>1 and 4 or 0)
		end
		if total<avail then
			for i=1,n do widths[i]+=(avail-total)/n end
			total=avail
		end
		strip={widths=widths,total=total,avail=avail}
	end
	local holder
	if strip then
		holder=listItem(make("ScrollingFrame",scroll,{BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.new(1,-7,0,height+inset*2),
			ScrollingDirection=Enum.ScrollingDirection.X,CanvasSize=UDim2.fromOffset(strip.total+inset*2,0),ScrollBarThickness=0,
			ElasticBehavior=Enum.ElasticBehavior.WhenScrollable,Selectable=false}))
		rows,per=1,n
	else
		holder=container(rows*height+(rows-1)*4+inset*2)
	end
	holder.Name=opts.small and "Filters" or "Sections"
	holder.BackgroundColor3=track
	holder.BackgroundTransparency=opts.small and .45 or .2
	make("UICorner",holder,{CornerRadius=UDim.new(0,(height+inset*2)//2)})
	make("UIStroke",holder,{Color=UI.line,Thickness=1,Transparency=0})
	local x=inset
	for i,name in ipairs(options) do
		local r,c=(i-1)//per,(i-1)%per
		local on=name==selected
		local position,size=UDim2.new(c/per,c==0 and inset or inset//2,0,inset+r*(height+4)),UDim2.new(1/per,(c==0 or c==per-1) and -inset*1.5 or -inset,0,height)
		if strip then
			position,size=UDim2.fromOffset(math.floor(x),inset),UDim2.fromOffset(math.floor(strip.widths[i]),height)
			if on then holder.CanvasPosition=Vector2.new(math.clamp(x-(strip.avail-strip.widths[i])/2,0,math.max(0,strip.total-strip.avail)),0) end
			x+=strip.widths[i]+4
		end
		local b=make("TextButton",holder,{Name=(opts.prefix or "Section")..(tostring(name):gsub("[^%w]","")),Text=tostring(name),AutoButtonColor=false,Selectable=true,BorderSizePixel=0,
			Position=position,Size=size,
			BackgroundColor3=on and (opts.small and mint or gold) or slate,BackgroundTransparency=on and 0 or 1,
			Font=on and UI.heavy or bold,TextColor3=on and (opts.small and deep or UI.onGold) or muted,TextScaled=true})
		make("UICorner",b,{CornerRadius=UDim.new(0,height//2)})
		make("UITextSizeConstraint",b,{MinTextSize=11,MaxTextSize=compactAtlas and 13 or 14})
		make("UIPadding",b,{PaddingLeft=UDim.new(0,6),PaddingRight=UDim.new(0,6),PaddingTop=UDim.new(0,4),PaddingBottom=UDim.new(0,4)})
		if on then
			UI.sheen(b,1,.74)
			make("UIStroke",b,{Color=UI.white,Thickness=1,Transparency=.55})
		end
		pressable(b)
		b.Activated:Connect(function() onPick(name) end)
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

-- Combat styles helpers (Data.CombatStyles, Data.Spells) shared by the Hero ›
-- Combat and Spellbook pages, item details and the bestiary. One table: the
-- chunk is at Luau's top-level local limit.
UI.CB={looks={melee={glyph="⚔",hex="F3C66E",name="Melee"},ranged={glyph="➶",hex="9BD67E",name="Ranged"},magic={glyph="✦",hex="8FA8FF",name="Magic"}}}
do
	local CB=UI.CB
	function CB.cs() return Data and type(Data.CombatStyles)=="table" and Data.CombatStyles or nil end
	function CB.styleOf(def)
		if type(def)=="table" and CB.looks[def.style] then return def.style end
		return "melee"
	end
	-- "✦ Magic" in the style's colour.
	function CB.tag(style)
		local look=CB.looks[style] or CB.looks.melee
		return paint(look.glyph.." "..look.name,look.hex)
	end
	function CB.spell(id) return Data and type(Data.Spells)=="table" and type(id)=="string" and Data.Spells[id] or nil end
	-- Wood tier names whose bows accept arrows of `tier` (bow maxAmmoTier = wood index + 1).
	function CB.bowsFor(tier)
		local cs=CB.cs()
		for _,t in ipairs(cs and tbl(cs.woodTiers) or EMPTY) do
			if num(t.index,0)+1>=tier then return t.prefix end
		end
		return nil
	end
	function CB.arrowName(tier)
		local cs=CB.cs()
		local t=cs and tbl(cs.arrowTiers)[tier]
		return type(t)=="table" and t.arrow and itemName(t.arrow) or ("tier "..tier.." arrows")
	end
	-- Detail lines for weapons (style, power, speed, reach, ammo, elements) and arrows.
	function CB.itemLines(def)
		local lines={}
		if type(def)~="table" then return lines end
		local cs=CB.cs()
		if def.kind=="weapon" then
			local style=CB.styleOf(def)
			if style=="ranged" and type(def.ranged)=="table" then
				local r=def.ranged
				table.insert(lines,CB.tag(style).." weapon  ·  Power "..fmt(num(r.power,0)).."  ·  "..string.format("%.2fs",num(r.speed,1)).." per shot  ·  Reach "..fmt(num(r.range,40)).." studs")
				local maxTier=num(r.maxAmmoTier,1)
				table.insert(lines,"Quiver: arrows up to tier "..maxTier.." ("..escape(CB.arrowName(1)).." … "..escape(CB.arrowName(maxTier))..")")
			elseif style=="magic" and type(def.magic)=="table" then
				local m=def.magic
				local elements=tbl(m.elements)
				table.insert(lines,CB.tag(style).." weapon  ·  Power +"..fmt(num(m.power,0)).." spell damage  ·  "..string.format("%.2fs",num(m.speed,1.2)).." per cast")
				if #elements>0 then
					local names={}
					for _,element in ipairs(elements) do
						local e=cs and tbl(cs.elements)[element]
						table.insert(names,paint(escape(element),type(e)=="table" and e.color or "C9F2FF"))
					end
					table.insert(lines,"Elemental staff: supplies unlimited "..table.concat(names,", ").." glyphs")
				else
					table.insert(lines,"Wand: quick casts, no free glyphs")
				end
			else
				table.insert(lines,CB.tag("melee").." weapon  ·  sword reach")
			end
		elseif type(def.ammo)=="table" then
			local tier=num(def.ammo.tier,1)
			local bows=CB.bowsFor(tier)
			table.insert(lines,CB.tag("ranged").." ammunition  ·  Tier "..tier.."  ·  +"..fmt(num(def.ammo.power,0)).." arrow power")
			table.insert(lines,bows and ("Fits "..escape(bows).." bows and stronger (bow arrow tier "..tier.."+)") or "No bow can fire these yet")
		end
		return lines
	end
	-- "Attacks ⚔ Melee · Weak to ✦ Magic (+30%) · Resists ➶ Ranged (−30%)"
	function CB.triangle(monster)
		if type(monster)~="table" or not monster.attackStyle then return nil end
		local cs=CB.cs()
		local bonus=cs and math.floor(num(cs.weaknessBonus,.3)*100+.5) or 30
		local penalty=cs and math.floor(num(cs.resistPenalty,.3)*100+.5) or 30
		local parts={"Attacks "..CB.tag(monster.attackStyle)}
		if monster.weakness then table.insert(parts,"Weak to "..CB.tag(monster.weakness)..paint(" +"..bonus.."%","FFD24A")) end
		if monster.defenceStyle then table.insert(parts,"Resists "..CB.tag(monster.defenceStyle)..paint(" −"..penalty.."%","A9BDC1")) end
		return table.concat(parts,"  ·  ")
	end
	-- Glyph costs per cast given a wielded weapon: {id, n, free} sorted by name.
	function CB.costs(spell,weapon)
		local cs=CB.cs()
		local free={}
		if type(weapon)=="table" and type(weapon.magic)=="table" and cs then
			for _,element in ipairs(tbl(weapon.magic.elements)) do
				local e=tbl(cs.elements)[element]
				if type(e)=="table" then free[e.glyph]=true end
			end
		end
		local out={}
		for id,n in pairs(tbl(spell.costs)) do table.insert(out,{id=id,n=num(n,1),free=free[id]==true}) end
		table.sort(out,function(a,b) return itemName(a.id)<itemName(b.id) end)
		return out
	end
	-- Expected spell damage (Progression.spellDamage): (damage + weapon power)
	-- × (1 + Int/100 × scaling) × (1 + Ability Damage%) × (1 + 3% per Magic level above 1).
	function CB.spellDamage(spell,stats,weapon,magic)
		if not spell.damage then return nil end
		local power=num(spell.damage,0)+(type(weapon)=="table" and type(weapon.magic)=="table" and num(weapon.magic.power,0) or 0)
		local dmg=power*(1+math.max(0,num(stats.intelligence,0))/100*num(spell.scaling,0))*(1+num(stats.abilityDamage,0)/100)*(1+.03*(math.max(1,magic)-1))
		return math.max(1,math.floor(dmg))
	end
	-- depth.combat with safe defaults.
	function CB.loadout()
		local c=tbl(dget("combat"))
		return {style=CB.looks[c.style] and c.style or "melee",weapon=type(c.weapon)=="string" and c.weapon or nil,ammo=type(c.ammo)=="string" and c.ammo or nil,
			ammoCount=num(c.ammoCount,0),supplies=tbl(c.supplies),levels=tbl(c.levels),autocast=type(c.autocast)=="string" and c.autocast or nil}
	end
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
UI.nextGoal = nextGoal -- §31: UI.objective() falls back to it
do
local function routeChart()
	local chart=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,144),slate))
	rounded(chart,10,gold)
	make("UIGradient",chart,{Color=ColorSequence.new(rgb("34716E"),rgb("112A3A")),Rotation=25})
	label(chart,"THE FIRST CROSSING",14,8,UDim.new(1,-24),19,UI.heavy,11,gold)
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
		if Pages.SYS then Pages.SYS.helperCard("contract","Quest helper  ·  guild contract") end -- §33
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
local function checkItem(o,pair)
	local ok,text=pcall(Data.describeCheck,o)
	text=ok and type(text)=="string" and text or "Task"
	local have,need=num(tbl(pair)[1],0),num(tbl(pair)[2],num(type(o)=="table" and (o.count or o.level or o.tier) or 1,1))
	local met=have>=need
	return {text=escape(text),met=met,amount=need>1 and (fmt(have).." / "..fmt(need)) or nil},met
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
			-- Grouped checklists (requirements, then tasks) and a rewards line.
			local requires,tasks={},{}
			if entry.done~=true then
				for i,o in ipairs(q.requires) do table.insert(requires,(checkItem(o,tbl(entry.requires)[i]))) end
				for i,o in ipairs(q.objectives) do table.insert(tasks,(checkItem(o,tbl(entry.objectives)[i]))) end
			end
			local lines={"<b>"..paint("REWARDS  ","F3C66E").."</b>"..rewardText(q.rewards)}
			local function checklists(body,nextOrder)
				if #requires>0 then UI.checklist(body,nextOrder,"REQUIRES",requires) end
				if #tasks>0 then UI.checklist(body,nextOrder,"TASKS",tasks) end
			end
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
			local guideAfter=Pages.SYS and Pages.SYS.questExtras(q,entry,actions,lines) -- §33 quest helper: NEXT line, Guide / Pin / Waypoint
			card({name="Quest"..q.id,motif="Journal",title=escape(q.title),titleColor=entry.done==true and muted or ivory,
				subtitle=escape((region and region.name or q.region).."  ·  "..(q.line=="main" and "Main quest" or "Side quest")),
				badge=badge,badgeColor=color,detail=entry.done~=true and escape(q.story or "") or nil,before=checklists,lines=lines,actions=actions,
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
				end or guideAfter})
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
	if Pages.SYS then Pages.SYS.helperCard("diary:"..QJ.region,"Quest helper  ·  current tier") end -- §33
	local tiers={}
	for _,t in ipairs(tbl(entry.tiers)) do if type(t)=="table" and type(t.tier)=="string" then tiers[t.tier]=t end end
	for index,tierName in ipairs(Data.DiaryTiers) do
		local def=diary.tiers[tierName]
		local t=tiers[tierName] or EMPTY
		local items,done={},0
		for i,o in ipairs(def.tasks) do
			local item,met=checkItem(o,tbl(t.tasks)[i])
			if met then done+=1 end
			table.insert(items,item)
		end
		local lines={"<b>"..paint("REWARD  ","F3C66E").."</b>Perk  "..escape(statText(def.perk)).."  ·  "..fmt(Data.DiaryCoins[tierName]).." coins"}
		local isClaimed=t.claimed==true or index<=claimed
		local badge,color="IN PROGRESS",ivory
		if isClaimed then badge,color="CLAIMED",mint
		elseif t.claimable==true then badge,color="READY",gold
		elseif index>claimed+1 then badge,color="LOCKED",ember end
		card({name="Diary"..QJ.region..tierName,motif="Hunt",title=tierName,titleColor=isClaimed and mint or ivory,badge=badge,badgeColor=color,
			before=function(body,nextOrder) UI.checklist(body,nextOrder,nil,items) end,lines=lines,bar={fraction=done/#def.tasks,color=isClaimed and mint or gold,caption=done.." / "..#def.tasks.." tasks"},
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
-- Island placement (Island Builder team): free-form props on the home island.
-- Place/Pick-up mode hands off to the IslandBuilder LocalScript through local
-- player attributes: IslandBuildMode ("place"|"remove"), IslandBuildProp and a
-- bumped IslandBuildRequest. The builder answers with IslandPlaceRequest
-- ("propId:x:z:rot") / IslandPickupRequest (placement id) plus a bumped
-- counter; this page sends the verbs so snapshots and toasts stay in one place.
QJ.mode="Terrace"
QJ.category="Fences"
function QJ.startBuild(mode,propId)
	player:SetAttribute("IslandBuildMode",mode)
	player:SetAttribute("IslandBuildProp",propId or "")
	player:SetAttribute("IslandBuildRequest",(num(player:GetAttribute("IslandBuildRequest"),0))+1)
	closeAtlas()
end
player:GetAttributeChangedSignal("IslandPlaceCount"):Connect(function()
	local value=player:GetAttribute("IslandPlaceRequest")
	if type(value)=="string" and #value<=40 and send then send("place",value) end
end)
player:GetAttributeChangedSignal("IslandPickupCount"):Connect(function()
	local value=player:GetAttribute("IslandPickupRequest")
	if type(value)=="string" and value:match("^%d+$") and #value<=4 and send then send("pickup",value) end
end)
function QJ.drawIsland(con)
	local I=Data.Island
	local isle=tbl(con.island)
	local carpentry=num(con.carpentry,1)
	local counts=tbl(isle.counts)
	local placedCount=math.max(0,math.floor(num(isle.count,0)))
	local cap=num(isle.cap,I.MAX_PLACEMENTS)
	local value=num(isle.value,0)
	local tierIndex,tier=I.tier(value)
	local nextTier=I.ValueTiers[tierIndex+1]
	card({name="IslandSummary",motif="Workshop",title="Island value "..fmt(value),titleColor=gold,
		subtitle=escape(type(isle.tierName)=="string" and isle.tierName or tier.name).."  ·  "..fmt(placedCount).." / "..fmt(cap).." props placed",
		lines={"Place decor anywhere on your home island grid. Spawn, workers, signs and bridges stay clear.",
			"Picking up returns 100% of materials. Carpentry XP is earned once per copy."},
		bar={fraction=nextTier and (value-tier.at)/(nextTier.at-tier.at) or 1,color=gold,caption=nextTier and (fmt(value).." / "..fmt(nextTier.at).."  ·  next: "..nextTier.name) or "Highest island tier"},
		actions={{caption="Pick up",name="IslandRemoveMode",disabled=placedCount==0,reason="Nothing is placed on your island yet.",fn=function() QJ.startBuild("remove") end}}})
	if not I.CategoryOf[QJ.category] then QJ.category=I.Categories[1] end
	sectionBar(I.Categories,QJ.category,function(name) QJ.category=name render() end,{small=true,prefix="PropCategory",maxPer=compactAtlas and 4 or 8})
	-- Latest placement id per prop (for the quick pick-up action), from the
	-- records the server replicates as the IslandPlacements attribute.
	local latest={}
	for _,e in ipairs(I.decode(player:GetAttribute("IslandPlacements"))) do
		if (latest[e.prop] or 0)<e.id then latest[e.prop]=e.id end
	end
	for _,id in ipairs(I.PropOrder) do
		local def=I.Props[id]
		if def.category==QJ.category then
			local have=math.max(0,math.floor(num(counts[id],0)))
			local costs,funded=costLine(def.costs)
			local levelOk=carpentry>=def.level
			local reason=if not levelOk then "Requires Carpentry "..def.level.."."
				elseif have>=def.max then "You have placed the most allowed ("..def.max..")."
				elseif placedCount>=cap then "Your island is full. Pick something up first."
				elseif not funded then "Gather the materials first." else nil
			local w,d=def.size[1],def.size[2]
			local extra={}
			if def.effect and def.effect.station then table.insert(extra,"Home "..def.effect.station.." station") end
			if def.effect and def.effect.light then table.insert(extra,"Glows at night") end
			local actions={{caption="Place",primary=reason==nil,disabled=reason~=nil,reason=reason,fn=function() QJ.startBuild("place",id) end}}
			if latest[id] then table.insert(actions,1,{caption="Pick up",fn=function() send("pickup",tostring(latest[id])) end}) end
			card({name="Prop"..id,motif="Workshop",title=escape(def.name),titleColor=levelOk and ivory or muted,
				subtitle=(levelOk and check or cross).." Carpentry "..def.level.."  ·  +"..fmt(def.xp).." XP  ·  "..w.."×"..d.." cells  ·  value "..def.value,
				badge=fmt(have).." / "..fmt(def.max),badgeColor=have>0 and mint or muted,
				detail=escape(def.text)..(#extra>0 and ("  "..paint(table.concat(extra,"  ·  "),"9EE7D2")) or ""),lines={costs},actions=actions})
		end
	end
end
local function drawConstruction()
	local island=Data and type(Data.Island)=="table"
	heading(if island and QJ.mode=="Island" then "HOME ISLAND    /    FREE PLACEMENT" else "BUILDER'S TERRACE    /    CARPENTRY")
	if island then sectionBar({"Terrace","Island"},QJ.mode,function(name) QJ.mode=name render() end,{small=true,prefix="BuildMode"}) end
	if island and QJ.mode=="Island" then
		local j=journal()
		if not j then syncing("island plans") return end
		QJ.drawIsland(tbl(j.construction))
		return
	end
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
		elseif need and def.slot=="ammo" then
			add(need,"Loose "..escape(def.name).."s",id)
		end
	end
	for _,region in ipairs(tbl(Data.Regions)) do
		local need=num(tbl(tbl(region.requires).skills)[skill],nil)
		if need then add(need,"Enter "..escape(region.name),nil) end
	end
	if skill=="Magic" then
		for _,spell in pairs(tbl(Data.Spells)) do add(spell.level,"Cast "..escape(spell.name),nil) end
	end
	if skill=="Enchanting" then
		for _,enchant in pairs(tbl(Data.Enchants)) do add(enchant.level,"Learn "..escape(enchant.name).." I",nil) end
	end
	-- Agility courses and shortcuts; Hunter creatures and extra trap slots.
	if skill=="Agility" and type(Data.Agility)=="table" then
		for _,course in ipairs(tbl(Data.Agility.Courses)) do add(course.level,"Run the "..escape(course.name),nil) end
		for _,sc in ipairs(tbl(Data.Agility.Shortcuts)) do add(sc.level,"Use the "..escape(sc.name).." shortcut",nil) end
	end
	if skill=="Hunter" and type(Data.Hunter)=="table" then
		for _,creature in ipairs(tbl(Data.Hunter.Creatures)) do
			local method=tbl(tbl(Data.Hunter.Methods)[creature.method])
			add(creature.level,(method.trap and "Trap " or "Net ")..escape(creature.name).." ("..escape(string.lower(method.name or "")).."), +"..fmt(creature.xp).." XP",tbl(creature.drops[1]).item)
		end
		for need=20,80,20 do add(need,"Tend "..(1+need//20).." traps at once",nil) end
	end
	-- Prayer: the prayer book; Thieving: stalls, marks and strongboxes.
	if skill=="Prayer" and type(Data.Prayer)=="table" then
		for _,def in ipairs(tbl(Data.Prayer.Prayers)) do add(def.level,"Pray "..escape(def.name)..": "..escape(def.text),nil) end
	end
	if skill=="Thieving" and type(Data.Thieving)=="table" then
		for _,t in ipairs(tbl(Data.Thieving.Targets)) do add(t.level,escape(tbl(Data.Thieving.Kinds[t.kind]).verb or "Rob").." the "..escape(t.name)..", +"..fmt(t.xp).." XP",nil) end
	end
	-- Beaconry (§37): logs, beacon pyres, strikers and the Everflame mantle.
	if skill=="Beaconry" and type(Data.Beaconry)=="table" and type(Data.Beaconry.unlocks)=="function" then
		for _,u in ipairs(Data.Beaconry.unlocks()) do add(u.level,escape(u.text),u.item) end
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
	if Pages.mastery then Pages.mastery.milestones(skill,info) end -- Skill Mastery: milestones, titles, mantle
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
		detail="Every level grants permanent stats and coins. Tap a skill to see what unlocks next.",
		lines={Pages.mastery and Pages.mastery.summary() or nil}})
	if selectedSkill and levels[selectedSkill] then drawSkillDetail(selectedSkill,levels[selectedSkill]) heading("ALL SKILLS") end
	local width=contentWidth()
	local columns=width>=690 and 3 or (width>=400 and 2 or 1)
	local cellHeight=compactAtlas and 108 or 122
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
		local on=selectedSkill==skill
		make("UIStroke",tileButton,{Color=on and gold or color,Transparency=on and 0 or .5,Thickness=on and 2 or 1})
		-- Skill medallion: level number on a skill-coloured disc.
		local medal=make("Frame",tileButton,{Name="Medal",Position=UDim2.fromOffset(10,10),Size=UDim2.fromOffset(compactAtlas and 34 or 40,compactAtlas and 34 or 40),BackgroundColor3=color,BorderSizePixel=0})
		make("UICorner",medal,{CornerRadius=UDim.new(1,0)})
		make("UIGradient",medal,{Rotation=90,Color=ColorSequence.new(UI.white,Color3.new(.42,.42,.42))})
		local medalRim=make("UIStroke",medal,{Color=on and gold or rgb(lighten(hex,.45)),Thickness=1.5,Transparency=.1})
		local medalText=label(medal,info.maxed and "★" or tostring(info.level),0,0,full,40,book,compactAtlas and 15 or 18,UI.white)
		medalText.Size=UDim2.fromScale(1,1)
		medalText.TextXAlignment=Enum.TextXAlignment.Center
		medalText.TextStrokeTransparency=.35
		medalText.TextStrokeColor3=deep
		local textX=compactAtlas and 52 or 60
		label(tileButton,skill,textX,compactAtlas and 9 or 10,UDim.new(1,-textX-60),20,UI.heavy,compactAtlas and 14 or 16,ivory)
		local mantle=info.maxed and Pages.mastery and Pages.mastery.wornCape()==skill -- Skill Mastery: worn skillcape
		local levelText=label(tileButton,mantle and "MANTLE" or (info.maxed and "MAX" or ("/ "..maxLevel())),0,compactAtlas and 9 or 11,UDim.new(0,50),20,bold,compactAtlas and 12 or 12,mantle and gold or muted)
		levelText.Position=UDim2.new(1,-58,0,compactAtlas and 9 or 11)
		levelText.TextXAlignment=Enum.TextXAlignment.Right
		local reward=label(tileButton,statText(skillDef(skill).perLevel,1,"  "),12,compactAtlas and 50 or 58,UDim.new(1,-20),compactAtlas and 18 or 20,regular,compactAtlas and 12 or 12,muted)
		reward.RichText=true
		local bar=progress(tileButton,info.fraction,color,nil,compactAtlas and 10 or 12)
		bar.Position=UDim2.new(0,12,0,compactAtlas and 72 or 82)
		bar.Size=UDim2.new(1,-24,0,compactAtlas and 10 or 12)
		local remaining=info.maxed and (fmt(info.xp).." XP  ·  mastered") or (fmt(math.max(0,info.ceiling-info.xp)).." XP to "..(info.level+1))
		label(tileButton,remaining,12,compactAtlas and 86 or 98,UDim.new(1,-80),18,bold,compactAtlas and 12 or 12,muted)
		local pct=label(tileButton,info.maxed and "100%" or (math.floor(info.fraction*1000+.5)/10 .."%"),0,compactAtlas and 86 or 98,UDim.new(0,64),18,UI.heavy,compactAtlas and 12 or 12,rgb(lighten(hex,.35)))
		pct.Position=UDim2.new(1,-76,0,compactAtlas and 86 or 98)
		pct.TextXAlignment=Enum.TextXAlignment.Right
	end
end

local selectedSlot="weapon"
-- Stat sheet: two cards (Combat · Gathering & luck), each a clean list of
-- glyph chip, name and right-aligned value with zebra rows.
local function drawStatSheet(stats)
	local groups={{title="COMBAT",keys={}},{title="GATHERING & LUCK",keys={}}}
	local gathering={miningSpeed=true,miningFortune=true,foragingFortune=true,farmingFortune=true,fishingFortune=true,seaCreatureChance=true,magicFind=true,petLuck=true,
		surefoot=true,trapLuck=true,huntingFortune=true}
	local keys={}
	for _,key in ipairs(Data and Data.StatOrder or {}) do table.insert(keys,key) end
	for _,key in ipairs({"effectiveHealth","damage","magicalPower","combatBonus"}) do table.insert(keys,key) end
	for _,key in ipairs(keys) do
		if num(stats[key],nil) then table.insert(groups[gathering[key] and 2 or 1].keys,key) end
	end
	local width=contentWidth()
	local columns=width>=420 and 2 or 1
	local rowHeight=compactAtlas and 24 or 28
	local holder=container()
	holder.Name="StatSheet"
	make("UIGridLayout",holder,{CellSize=UDim2.new(1/columns,-8,0,0),CellPadding=UDim2.fromOffset(8,8),SortOrder=Enum.SortOrder.LayoutOrder})
	local tallest=0
	for _,group in ipairs(groups) do tallest=math.max(tallest,#group.keys) end
	holder:FindFirstChildOfClass("UIGridLayout").CellSize=UDim2.new(1/columns,columns>1 and -4 or 0,0,30+tallest*rowHeight+12)
	for g,group in ipairs(groups) do
		local sheet=make("Frame",holder,{Name="Stats"..g,BackgroundColor3=deep,BorderSizePixel=0,LayoutOrder=g})
		make("UICorner",sheet,{CornerRadius=UDim.new(0,12)})
		make("UIStroke",sheet,{Color=UI.line,Thickness=1})
		UI.sheen(sheet,1,.8)
		UI.bevel(sheet,12,.88)
		local cap=label(sheet,group.title,14,6,UDim.new(1,-28),20,UI.heavy,11,gold)
		cap.Name="Caption"
		UI.rule(sheet,UI.brass,28,10).BackgroundTransparency=.4
		for i,key in ipairs(group.keys) do
			local def=statDef(key)
			local y=34+(i-1)*rowHeight
			local line=make("Frame",sheet,{Name="Stat"..key,Position=UDim2.fromOffset(6,y),Size=UDim2.new(1,-12,0,rowHeight),BackgroundColor3=UI.white,BackgroundTransparency=i%2==0 and .965 or 1,BorderSizePixel=0})
			make("UICorner",line,{CornerRadius=UDim.new(0,6)})
			local hex=lighten(def.color or "FFFFFF",.15)
			local chip=make("TextLabel",line,{Name="Glyph",AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,4,.5,0),Size=UDim2.fromOffset(rowHeight-6,rowHeight-6),BackgroundColor3=rgb(hex),BackgroundTransparency=.82,
				Text=def.symbol or "•",Font=UI.heavy,TextSize=compactAtlas and 12 or 13,TextColor3=rgb(hex),BorderSizePixel=0})
			make("UICorner",chip,{CornerRadius=UDim.new(1,0)})
			local name=label(line,def.name or key,rowHeight+6,0,UDim.new(1,-rowHeight-80),rowHeight,regular,compactAtlas and 12 or 13,UI.copy)
			name.Name="Name"
			local amount=label(line,statValue(key,num(stats[key],0)),0,0,UDim.new(0,72),rowHeight,UI.heavy,compactAtlas and 13 or 14,ivory)
			amount.Position=UDim2.new(1,-78,0,0)
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
		local slotText=label(slotTile,string.upper(slotNames[slot]),0,iconSize+8,full,14,UI.heavy,11,gold)
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
		local equippedLines={#enchants>0 and paint("Enchanted: "..table.concat(enchants,", "),"7FD3E3") or nil,def.set and Data.Sets[def.set] and ("Set: "..escape(Data.Sets[def.set].name).." — "..escape(Data.Sets[def.set].text)) or nil}
		for _,line in ipairs(UI.Gear.lines(id)) do table.insert(equippedLines,line) end -- Gear depth layers
		card({name="Equipped"..selectedSlot,item=id,title=UI.Gear.title(id),titleColor=rgb(UI.Gear.hex(id)),subtitle=escape(UI.Gear.rarity(id).." "..kindLabel(def)),badge="EQUIPPED",badgeColor=mint,
			detail=statText(def.stats),lines=equippedLines,
			actions={{caption="Enchant",fn=function() enchantTarget=id;sectionOf.Hero="Enchant";scroll.CanvasPosition=Vector2.zero;render() end},
				{caption="Reforge",fn=function() UI.Gear.open(id) end},
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
		if equippedSlotOf(id) then UI.tag(pick,"E") end
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
		lines={"Duplicates do not stack; only the best piece of a gem's jewellery family counts; highest rarity fills slots first. +1 slot every "..every.." "..tostring(tbl(rule.slotsPerLevel).skill or "Combat").." levels (max "..num(rule.maxSlots,24)..")."},
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
		-- A bagged jewellery piece outranked by a better piece of its gem family.
		local outranked=false
		if isBagged and not isActive and def.gem then
			for other in pairs(active) do if itemDef(other).gem==def.gem then outranked=true end end
		end
		local status=label(entry,isActive and "ACTIVE" or (outranked and "FAMILY" or (isBagged and "NO SLOT" or "ADD")),0,compactAtlas and 5 or 7,UDim.new(0,70),18,UI.heavy,11,isActive and mint or (isBagged and gold or muted))
		status.Position=UDim2.new(1,-76,0,compactAtlas and 5 or 7)
		status.TextXAlignment=Enum.TextXAlignment.Right
		if power then
			local mp=label(entry,"✧ "..power,0,compactAtlas and 38 or 44,UDim.new(0,70),14,UI.heavy,11,rgb("FFAA00"))
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
-- Hero › Pets (Pets depth): roster grid with rarity frames and XP bars; the
-- selected pet's abilities (locked/unlocked), held item, candy and Roost
-- upgrade; the Roost job timer; adoption, the Roost keeper's stall and the
-- compendium. Helpers live on UI.PT (the chunk is near Luau's local limit).
UI.PT={sel=1}
function UI.PT.rarity(r) return type(r)=="string" and r or "Common" end
-- "+12.5 Strength, +3% Sea Creature Chance" (sorted, one decimal).
function UI.PT.statLine(stats)
	local parts={}
	for key,v in pairs(tbl(stats)) do
		local value=num(v,0)
		if value~=0 then
			local def=tbl(tbl(Data.Stats)[key])
			local name=key=="damagePercent" and "Damage" or tostring(def.name or key)
			local pct=def.percent==true or key=="damagePercent"
			table.insert(parts,"+"..(math.floor(value*10+.5)/10)..(pct and "%" or "").." "..escape(name))
		end
	end
	table.sort(parts)
	return #parts>0 and table.concat(parts,", ") or "none yet"
end
function UI.PT.costLine(cost)
	local parts={}
	if num(tbl(cost).coins,0)>0 then table.insert(parts,paint(fmt(cost.coins).." coins","F3C66E")) end
	local ids={}
	for id in pairs(tbl(tbl(cost).items)) do table.insert(ids,id) end
	table.sort(ids)
	for _,id in ipairs(ids) do
		local need=num(cost.items[id],0)
		local have=count("items",id)
		table.insert(parts,paint(fmt(have).."/"..fmt(need),have>=need and "9EE7D2" or "E8806A").." "..paint(escape(itemName(id)),itemHex(id)))
	end
	return table.concat(parts,"  ·  ")
end
function UI.PT.affordable(cost)
	if num(state.coins,0)<num(tbl(cost).coins,0) then return false,"Not enough coins." end
	for id,n in pairs(tbl(tbl(cost).items)) do
		if count("items",id)<num(n,0) then return false,"Needs "..fmt(n).." "..itemName(id).."." end
	end
	return true
end
-- The Roost job: timer bar, Claim (once ready) and Cancel (only while the
-- timer runs, behind a Confirm step: the fee is never refunded).
function UI.PT.roost(info)
	local job=info.upgrade
	if type(job)~="table" then UI.PT.cancelConfirm=false return end
	local def=tbl(tbl(Data.PetById)[job.id])
	local PD=tbl(Data.PetDepth)
	local total=num(tbl(tbl(PD.Upgrade)[job.to]).seconds,1)
	local remaining=num(job.remaining,0)
	local ready=job.ready==true
	heading("THE ROOST    /    "..escape(tostring(PD.KEEPER or "Roost Keeper")))
	card({name="PetRoost",item=tostring(job.id).."Pet",title=escape(tostring(def.name or job.id)),titleColor=rgb(rarityHex(UI.PT.rarity(job.to))),
		subtitle=escape(tostring(job.from or "?")).." → "..paint(escape(tostring(job.to or "?")),rarityHex(UI.PT.rarity(job.to))).."  ·  Lv "..num(job.level,1),
		badge=ready and "READY" or clock(remaining),badgeColor=ready and mint or gold,
		detail=ready and "Your companion is ready to come home at its new rarity." or "Growing into its new rarity. Its lifetime XP is kept; the level is recounted on the new curve.",
		bar={fraction=ready and 1 or math.clamp(1-remaining/math.max(1,total),0,1),color=rgb(rarityHex(UI.PT.rarity(job.to))),caption=ready and "READY TO CLAIM" or (clock(remaining).." left")},
		actions=ready and {{caption="Claim",primary=true,name="PetClaimButton",fn=function() UI.PT.cancelConfirm=false;send("petClaim") end}}
			or {{caption="Claim",primary=true,name="PetClaimButton",disabled=true,reason="The Roost needs "..clock(remaining).." more.",fn=function() send("petClaim") end},
				UI.PT.cancelConfirm and {caption="Confirm",name="PetCancelConfirm",fn=function() UI.PT.cancelConfirm=false;send("petCancel") end}
					or {caption="Cancel",name="PetCancelButton",fn=function() UI.PT.cancelConfirm=true;render() end},
				UI.PT.cancelConfirm and {caption="Keep",name="PetCancelKeep",fn=function() UI.PT.cancelConfirm=false;render() end} or nil}})
	-- Cancelling early forfeits the whole fee (coins and materials).
	if UI.PT.cancelConfirm and not ready then para(container(),paint("Cancelling takes your pet home now at its old rarity. The Roost fee is not refunded. Confirm to cancel.","E8806A"),1,muted) end
end
-- One roster tile: rarity frame, icon, name, level, XP bar, summoned tag.
function UI.PT.tile(grid,index,pet,selected)
	local def=tbl(tbl(Data.PetById)[pet.id])
	local rarity=UI.PT.rarity(pet.rarity or def.rarity)
	local hex=rarityHex(rarity)
	local b=tile(grid,"PetTile"..index,index,function()
		UI.PT.sel=index
		render()
	end)
	make("UIStroke",b,{Name="RarityFrame",Color=rgb(hex),Thickness=selected and 2.5 or 1.5,Transparency=selected and 0 or .25})
	local icon=itemIcon(b,tostring(pet.id).."Pet",compactAtlas and 34 or 40)
	icon.Position=UDim2.fromOffset(8,8)
	local x=compactAtlas and 48 or 56
	local name=label(b,escape(tostring(def.name or pet.id or "Pet")),x,6,UDim.new(1,-x-6),18,UI.heavy,compactAtlas and 12 or 13,rgb(hex))
	name.RichText=true
	name.TextTruncate=Enum.TextTruncate.AtEnd
	label(b,"Lv "..num(pet.level,1).."  ·  "..rarity,x,24,UDim.new(1,-x-6),16,bold,11,muted)
	local nextXp=num(pet.next,nil)
	local maxed=num(pet.level,1)>=num(Data.PET_MAX_LEVEL,100)
	local bar=progress(b,maxed and 1 or ((nextXp and nextXp>0) and math.clamp(num(pet.xp,0)/nextXp,0,1) or 0),rgb(hex),nil,8)
	bar.Position=UDim2.new(0,8,1,-14)
	bar.Size=UDim2.new(1,-16,0,8)
	if pet.active==true then UI.tag(b,"S") end
	if type(pet.item)=="string" then
		local held=label(b,"◆",0,4,UDim.new(0,16),16,UI.heavy,12,gold)
		held.Position=UDim2.new(1,-20,0,4)
	end
	return b
end
-- Selected pet: stats, abilities, held item, candy, upgrade and actions.
function UI.PT.detail(index,pet)
	local def=tbl(tbl(Data.PetById)[pet.id])
	local PD=tbl(Data.PetDepth)
	local rarity=UI.PT.rarity(pet.rarity or def.rarity)
	local hex=rarityHex(rarity)
	local level=num(pet.level,1)
	local xp=num(pet.xp,0)
	local nextXp=num(pet.next,nil)
	local maxed=level>=num(Data.PET_MAX_LEVEL,100)
	local lines={}
	local stats=type(pet.stats)=="table" and pet.stats or nil
	if not stats then
		stats={}
		for k,v in pairs(tbl(def.perLevel)) do stats[k]=num(v,0)*level end
	end
	table.insert(lines,paint("Stats  ","BECECA")..UI.PT.statLine(stats))
	for _,a in ipairs(tbl(pet.abilities)) do
		if type(a)=="table" then
			local name=escape(tostring(a.name or "Ability"))
			if a.unlocked==true then
				table.insert(lines,paint("✦ "..name,"F9CC77").."  "..escape(tostring(a.text or "")))
			else
				table.insert(lines,paint("🔒 "..name,"8A9AA0").."  "..paint(escape(tostring(a.text or "")).."  ·  unlocks at "..escape(tostring(a.requires or "?")),"8A9AA0"))
			end
		end
	end
	local held=type(pet.item)=="string" and tbl(tbl(PD.HeldItems)[pet.item]) or nil
	table.insert(lines,paint("Held item  ","BECECA")..(held and (paint(escape(tostring(held.name or pet.item)),itemHex(pet.item)).."  ·  "..escape(tostring(held.text or ""))) or "empty"))
	local candy,candyMax=num(pet.candy,0),num(pet.candyMax,num(PD.CANDY_MAX,10))
	local cost=type(pet.upgrade)=="table" and pet.upgrade or nil
	if cost then table.insert(lines,paint("Roost → "..escape(tostring(cost.to)),rarityHex(UI.PT.rarity(cost.to))).."  "..clock(cost.seconds).."  ·  "..UI.PT.costLine(cost)) end
	local actions={}
	-- Pets depth verbs name the pet as "index:speciesId" (the server checks both).
	local ref=index..":"..tostring(pet.id)
	table.insert(actions,pet.active==true and {caption="Dismiss",fn=function() send("petSummon","0") end} or {caption="Summon",primary=true,fn=function() send("petSummon",tostring(index)) end})
	-- One button per candy type, so the player picks which to feed.
	for _,c in ipairs({{id="PetCandy",caption="Candy",button="PetCandyButton",none="Buy Pet Candy from the Roost keeper or cook it at the Hearth."},
		{id="StarlitCandy",caption="Starlit",button="StarlitCandyButton",none="Starlit Candy drops from tier 3+ slayer bosses or is cooked at the Hearth."}}) do
		local blocked=(candy>=candyMax and "This pet has eaten all its candy.") or (maxed and "Already level "..level..".") or (count("items",c.id)<1 and c.none) or nil
		if c.id=="PetCandy" or count("items",c.id)>0 then
			table.insert(actions,{caption=c.caption.." ×"..count("items",c.id),name=c.button,disabled=blocked~=nil,reason=blocked,fn=function() send("petCandy",ref..":"..c.id) end})
		end
	end
	if cost then
		local okCost,why=UI.PT.affordable(cost)
		local busy=type(tbl(dget("petDepth")).upgrade)=="table"
		table.insert(actions,{caption="Upgrade",name="PetUpgradeButton",disabled=busy or not okCost,reason=busy and "The Roost is caring for another pet." or why,fn=function() send("petUpgrade",ref) end})
	end
	card({name="PetDetail",item=tostring(pet.id).."Pet",title=escape(tostring(def.name or pet.id or "Pet")),titleColor=rgb(hex),edge=rgb(hex),
		subtitle="Lv "..level.."  ·  "..paint(rarity,hex).."  ·  "..escape(tostring(def.skill or "")).." pet",badge=pet.active==true and "SUMMONED" or nil,badgeColor=mint,
		lines=lines,pips=candyMax>0 and candyMax<=16 and {total=candyMax,filled=math.clamp(candy,0,candyMax),color=rgb("F7A1C4")} or nil,
		bar={fraction=maxed and 1 or ((nextXp and nextXp>0) and math.clamp(xp/nextXp,0,1) or 0),color=rgb(hex),caption=maxed and "MAX LEVEL" or (nextXp and (short(xp).." / "..short(nextXp).." XP") or (short(xp).." XP"))},
		actions=actions})
	if cost and count("items","AscendantPrism")>0 then
		card({name="PetPrism",item="AscendantPrism",title="Ascendant Prism  ×"..count("items","AscendantPrism"),titleColor=rgb(itemHex("AscendantPrism")),
			subtitle="Tier Boost  ·  "..paint(rarity,hex).." → "..paint(escape(tostring(cost.to)),rarityHex(UI.PT.rarity(cost.to))),
			detail="Raises this pet one rarity tier at once, skipping the Roost. Lifetime XP is kept.",
			actions={{caption="Use",primary=true,name="PetPrismButton",fn=function() send("petTierBoost",index..":"..tostring(pet.id)) end}}})
	end
	-- Held items: equip from the satchel, or take the current one off.
	local owned={}
	for _,id in ipairs(tbl(PD.HELD_ORDER)) do if count("items",id)>0 then table.insert(owned,id) end end
	if held or #owned>0 then
		heading("HELD ITEM    /    CANDY "..candy.."/"..candyMax)
		if held then
			card({name="PetHeldCurrent",item=pet.item,title=escape(tostring(held.name or pet.item)),titleColor=rgb(itemHex(pet.item)),subtitle="Held by "..escape(tostring(def.name or pet.id)),
				detail=escape(tostring(held.text or "")),actions={{caption="Remove",fn=function() send("petItem",index..":"..tostring(pet.id)..":none") end}}})
		end
		for _,id in ipairs(owned) do
			local h=tbl(PD.HeldItems[id])
			card({name="PetHeld"..id,item=id,title=escape(itemName(id)).."  ×"..count("items",id),titleColor=rgb(itemHex(id)),detail=escape(tostring(h.text or "")),
				actions={{caption="Equip",primary=true,fn=function() send("petItem",index..":"..tostring(pet.id)..":"..id) end}}})
		end
	end
end
local function drawPets()
	if not Data then dataMissing() return end
	local PT=UI.PT
	local PD=tbl(Data.PetDepth)
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
	local pets={}
	for index,pet in ipairs(tbl(d.pets)) do if type(pet)=="table" and tbl(Data.PetById)[pet.id] then table.insert(pets,{index=index,pet=pet}) end end
	local info=tbl(d.petDepth)
	PT.roost(info)
	local taming=tbl(info.taming)
	heading("COMPANIONS    /    "..#pets.." OWNED"..(taming.level and ("  ·  TAMING "..num(taming.level,1)) or ""))
	if taming.level then
		card({motif="Co-op",name="PetTaming",title="Taming "..num(taming.level,1),subtitle="+"..num(taming.xpBonus,0).."% pet XP  ·  +"..num(taming.statBonus,0).."% pet stats",
			detail="Pets share your skill XP: their own skill in full, the same kind of skill at half, the rest at a quarter. Their XP trains Taming."})
	end
	if #pets==0 then card({motif="Co-op",title="No companions yet",detail="Rare creature drops, slayer bosses and long hours at a skill yield pet items. Adopt them here."}) end
	if #pets>0 then
		local found=false
		for _,e in ipairs(pets) do if e.index==PT.sel then found=true end end
		if not found then PT.sel=pets[1].index end
		local width=contentWidth()
		local columns=width>=640 and 4 or (width>=420 and 3 or 2)
		local grid=gridHolder(UDim2.new(1/columns,-6,0,compactAtlas and 72 or 80),6)
		local chosen
		for _,e in ipairs(pets) do
			PT.tile(grid,e.index,e.pet,e.index==PT.sel)
			if e.index==PT.sel then chosen=e end
		end
		if chosen then PT.detail(chosen.index,chosen.pet) end
	end
	-- The Roost keeper's stall: compact tiles (tap to buy).
	local width=contentWidth()
	local cols=width>=640 and 3 or 2
	if #tbl(PD.Shop)>0 then
		heading("ROOST STALL    /    "..escape(tostring(PD.KEEPER or "Roost Keeper")))
		local grid=gridHolder(UDim2.new(1/cols,-6,0,compactAtlas and 46 or 50),6)
		for i,entry in ipairs(tbl(PD.Shop)) do
			if type(entry)=="table" and itemDef(entry.item) then
				local price=num(entry.coins,0)
				local b=tile(grid,"PetShop"..entry.item,i,function()
					if num(state.coins,0)<price then notify("You need "..fmt(price).." coins.") return end
					send("petShop",entry.item)
				end)
				-- §31: right-click opens the quantity picker (features.client.lua).
				b.MouseButton2Click:Connect(function()
					local left=Pages.SYS and Data.Systems and Pages.SYS.stockLeft(Data.Systems.Stock.key("roost",entry.item)) -- §33 daily stock caps the picker
					UI.pickQuantity({verb="petShop",base=entry.item,name=itemName(entry.item),unit=price,amount=1,max=math.min(UI.affordLots({coins=price}),math.max(1,left or 64))})
				end)
				make("UIStroke",b,{Color=rgb(itemHex(entry.item)),Thickness=1,Transparency=.35})
				local n=label(b,escape(itemName(entry.item)),10,4,UDim.new(1,-16),20,UI.heavy,compactAtlas and 12 or 13,rgb(itemHex(entry.item)))
				n.TextTruncate=Enum.TextTruncate.AtEnd
				local stock=Pages.SYS and Data.Systems and Pages.SYS.stockText(Data.Systems.Stock.key("roost",entry.item)) -- §33 daily stock
				local priceLabel=label(b,fmt(price).." coins"..(stock and ("  ·  "..stock) or ""),10,24,UDim.new(1,-16),18,bold,11,num(state.coins,0)>=price and gold or muted)
				priceLabel.RichText=true
			end
		end
	end
	-- Compendium: species not yet owned, as compact locked tiles with their source.
	local owned={}
	for _,e in ipairs(pets) do owned[e.pet.id]=true end
	local missing={}
	for _,pet in ipairs(tbl(Data.Pets)) do if type(pet)=="table" and not owned[pet.id] then table.insert(missing,pet) end end
	if #missing>0 then
		local sources=petSources()
		for skill,id in pairs(tbl(PD.SkillPets)) do
			sources[id]=sources[id] or {}
			table.insert(sources[id],tostring(skill).." training")
		end
		heading("PET COMPENDIUM    /    "..#missing.." TO FIND")
		local holder=gridHolder(UDim2.new(1/cols,-6,0,compactAtlas and 58 or 62),6)
		for i,pet in ipairs(missing) do
			local cell=make("Frame",holder,{Name="Compendium"..tostring(pet.id),BackgroundColor3=deep,BorderSizePixel=0,LayoutOrder=i})
			make("UICorner",cell,{CornerRadius=UDim.new(0,10)})
			make("UIStroke",cell,{Color=UI.line,Thickness=1})
			local n=label(cell,escape(tostring(pet.name)).."  "..paint(escape(tostring(pet.rarity).." "..tostring(pet.skill)),"8A9AA0"),10,4,UDim.new(1,-16),18,UI.heavy,compactAtlas and 12 or 12,muted)
			n.RichText=true
			n.TextTruncate=Enum.TextTruncate.AtEnd
			local from=sources[tostring(pet.id).."Pet"]
			local f=label(cell,from and ("From: "..escape(table.concat(from,", "))) or "Source unknown.",10,22,UDim.new(1,-16),34,regular,11,muted)
			f.TextWrapped=true
			f.TextYAlignment=Enum.TextYAlignment.Top
		end
	end
end

-- Hero › Combat: the wielded style, quiver, combat levels, the triangle and
-- owned weapons of every style (Combat Styles; snapshot depth.combat).
function Pages.drawCombat()
	local CB=UI.CB
	local cs=CB.cs()
	if not Data or not cs then dataMissing() return end
	local d=depth()
	if not d then syncing("combat loadout") return end
	local lo=CB.loadout()
	local stats=tbl(d.stats)
	local equipment=tbl(d.equipment)
	local levels=skillsOf(state)
	local weaponId=lo.weapon or (type(equipment.weapon)=="string" and equipment.weapon or nil)
	local weapon=itemDef(weaponId)
	local style=lo.style
	local look=CB.looks[style]
	heading("COMBAT STYLE")
	local lines=weapon and CB.itemLines(weapon) or {"Unarmed: a melee swing. Equip a sword, bow, staff or wand to change style."}
	local beats,beatenBy=tbl(cs.beats)[style],tbl(cs.beatenBy)[style]
	if beats then table.insert(lines,"Strong against "..CB.tag(beats).." fighters (+"..math.floor(num(cs.weaknessBonus,.3)*100+.5).."%)  ·  resisted by "..CB.tag(beatenBy).." fighters (−"..math.floor(num(cs.resistPenalty,.3)*100+.5).."%)") end
	if style=="magic" then
		local auto=CB.spell(lo.autocast)
		table.insert(lines,"Autocast: "..(auto and paint(escape(auto.name),auto.color) or paint("strongest unlocked spell","A9BDC1")).."  ·  set it in the Spellbook")
	end
	local maxMana=num(player:GetAttribute("MaxMana"),nil) or num(stats.intelligence,0)
	local mana=num(player:GetAttribute("Mana"),nil) or maxMana
	card({name="CombatStyle",item=weapon and weaponId or nil,motif=not weapon and "Hero" or nil,accent=rgb(look.hex),
		title=look.name.." style",titleColor=rgb(look.hex),subtitle=weapon and escape(weapon.name) or "Bare hands",badge=look.glyph.." "..string.upper(look.name),badgeColor=rgb(look.hex),
		lines=lines,bar={fraction=maxMana>0 and mana/maxMana or 0,color=rgb("5C8BFF"),caption="✦ Mana "..fmt(math.floor(mana)).." / "..fmt(math.floor(maxMana)).."  ·  +"..num(cs.manaRegenPercent,4).."% per second  ·  max = Intelligence"},
		actions={{caption="Spellbook",fn=function() sectionOf.Hero="Spellbook";scroll.CanvasPosition=Vector2.zero;render() end},
			{caption="Gear",fn=function() sectionOf.Hero="Gear";scroll.CanvasPosition=Vector2.zero;render() end}}})
	-- Quiver (ammo slot).
	heading("QUIVER    /    "..fmt(lo.ammoCount).." ARROWS")
	local ammoId=lo.ammo or (type(equipment.ammo)=="string" and equipment.ammo or nil)
	local ammo=itemDef(ammoId)
	local bowTier=weapon and type(weapon.ranged)=="table" and num(weapon.ranged.maxAmmoTier,nil) or nil
	if ammo then
		local ammoLines=CB.itemLines(ammo)
		if bowTier then
			local fits=num(tbl(ammo.ammo).tier,1)<=bowTier
			table.insert(ammoLines,fits and paint("✓ Fits your "..escape(weapon.name),"9EE7D2") or paint("✗ Too heavy for your "..escape(weapon.name).." (arrows up to tier "..bowTier..")","E8806A"))
		elseif style~="ranged" then
			table.insert(ammoLines,paint("Equip a bow to loose these arrows.","A9BDC1"))
		end
		card({name="Quiver",item=ammoId,title=escape(ammo.name).."  ×"..fmt(math.max(lo.ammoCount,count("items",ammoId))),titleColor=rgb(itemHex(ammoId)),
			subtitle="Quiver  ·  one arrow per shot",badge="QUIVER",badgeColor=mint,lines=ammoLines,
			actions={{caption="Unequip",fn=function() send("unequip","ammo") end}}})
	else
		card({name="Quiver",motif="Hunt",title="Empty quiver",titleColor=muted,detail="Fletch arrows at the Workbench (Fletching) from shafts, plumes and forged arrowheads, then equip them here. Every bow shot uses one arrow."})
	end
	local arrows={}
	for itemId,n in pairs(tbl(state.items)) do
		local def=itemDef(itemId)
		if num(n,0)>0 and def and def.slot=="ammo" and itemId~=ammoId then table.insert(arrows,itemId) end
	end
	table.sort(arrows,function(a,b) return num(tbl(itemDef(a).ammo).tier,0)>num(tbl(itemDef(b).ammo).tier,0) end)
	for _,arrowId in ipairs(arrows) do
		local def=itemDef(arrowId)
		local ok,requirements=meetsRequires(def.requires,levels)
		local tier=num(tbl(def.ammo).tier,1)
		local fits=not bowTier or tier<=bowTier
		card({name="Ammo"..arrowId,item=arrowId,iconSize=compactAtlas and 30 or 36,title=escape(def.name).."  ×"..fmt(count("items",arrowId)),titleColor=rgb(itemHex(arrowId)),
			subtitle="Tier "..tier.."  ·  +"..fmt(num(tbl(def.ammo).power,0)).." power"..(fits and "" or "  ·  too heavy for this bow"),
			lines={requirements~="" and ("Requires "..requirements) or nil},
			actions={{caption="Equip",primary=ok and fits,disabled=not ok,reason="Requires "..(requirements:gsub("<[^>]+>","")),fn=function() send("equip",arrowId) end}}})
	end
	-- Combat levels: melee trains Combat; ranged/magic train their own skill plus a Combat share.
	heading("COMBAT LEVELS")
	card({name="CombatLevels",motif="Hunt",title="Combat "..(levels.Combat and levels.Combat.level or 1),titleColor=gold,
		subtitle="Ranged "..(levels.Ranged and levels.Ranged.level or 1).."  ·  Magic "..(levels.Magic and levels.Magic.level or 1),
		detail="Melee hits train Combat. Bow and spell hits train Ranged or Magic, and a third of that XP also feeds Combat.",
		after=function(body,nextOrder)
			for _,skill in ipairs({"Combat","Ranged","Magic"}) do
				local info=levels[skill]
				if info then
					local glyph=skill=="Combat" and "⚔" or skill=="Ranged" and "➶" or "✦"
					progress(body,info.fraction,rgb(skillHex(skill)),glyph.." "..string.upper(skill).." "..info.level..(info.maxed and "  ·  MAX" or ("  ·  "..fmt(math.max(0,info.ceiling-info.xp)).." XP to "..(info.level+1)))).LayoutOrder=nextOrder()
				end
			end
		end})
	-- The triangle: three medallions in a ring of arrows.
	heading("THE COMBAT TRIANGLE")
	card({name="Triangle",motif="Hunt",title="Each style beats the next",titleColor=gold,
		after=function(body,nextOrder)
			local rowHeight=compactAtlas and 80 or 92
			local strip=make("Frame",body,{Name="TriangleStrip",BackgroundTransparency=1,Size=UDim2.new(1,0,0,rowHeight),LayoutOrder=nextOrder()})
			local order=tbl(cs.order)
			for i,name in ipairs(order) do
				local l=CB.looks[name]
				local x=(i-1)/#order+.5/#order
				local size=compactAtlas and 34 or 40
				local chip=UI.chip(strip,l.glyph,rgb(l.hex),size,0)
				chip.Name="Style"..name
				chip.AnchorPoint=Vector2.new(.5,0)
				chip.Position=UDim2.new(x,0,0,0)
				if name==style then make("UIStroke",chip,{Color=gold,Thickness=2}) end
				local caption=label(strip,l.name,0,size+2,UDim.new(0,90),16,UI.heavy,12,rgb(l.hex))
				caption.AnchorPoint=Vector2.new(.5,0)
				caption.Position=UDim2.new(x,0,0,size+3)
				caption.TextXAlignment=Enum.TextXAlignment.Center
				if i<#order then
					local arrow=label(strip,"beats ▶",0,0,UDim.new(0,70),size,bold,11,muted)
					arrow.AnchorPoint=Vector2.new(.5,0)
					arrow.Position=UDim2.new(i/#order,0,0,0)
					arrow.TextXAlignment=Enum.TextXAlignment.Center
				end
			end
			local back=label(strip,"◀ "..CB.looks[order[#order]].name.." beats "..CB.looks[order[1]].name,0,0,full,14,bold,11,muted)
			back.Position=UDim2.new(0,0,1,-15)
			back.TextColor3=rgb(CB.looks[order[#order]].hex)
			back.TextXAlignment=Enum.TextXAlignment.Center
			para(body,"Hit a creature with the style that beats its own for "..paint("+"..math.floor(num(cs.weaknessBonus,.3)*100+.5).."% WEAK!","FFD24A")..
				"; the style it beats is resisted ("..paint("−"..math.floor(num(cs.resistPenalty,.3)*100+.5).."%","A9BDC1").."). The Bestiary lists every creature's weakness.",nextOrder(),UI.copy,compactAtlas and 12 or 13)
		end})
	-- Owned weapons by style (the best two of each, strongest first).
	local byStyle={melee={},ranged={},magic={}}
	for itemId,n in pairs(tbl(state.items)) do
		local def=itemDef(itemId)
		if num(n,0)>0 and def and def.kind=="weapon" and itemId~=weaponId then table.insert(byStyle[CB.styleOf(def)],itemId) end
	end
	local any=false
	for _,name in ipairs(tbl(cs.order)) do if #byStyle[name]>0 then any=true end end
	if any then heading("SWITCH STYLE") end
	for _,name in ipairs(tbl(cs.order)) do
		local list=byStyle[name]
		table.sort(list,function(a,b)
			local da,db=itemDef(a),itemDef(b)
			if num(da.tier,0)~=num(db.tier,0) then return num(da.tier,0)>num(db.tier,0) end
			return da.name<db.name
		end)
		for i=1,math.min(2,#list) do
			local itemId=list[i]
			local def=itemDef(itemId)
			local ok,requirements=meetsRequires(def.requires,levels)
			local detail=CB.itemLines(def)
			card({name="Weapon"..itemId,item=itemId,iconSize=compactAtlas and 30 or 36,title=escape(def.name),titleColor=rgb(itemHex(itemId)),subtitle=CB.tag(name).."  ·  "..escape(def.rarity or ""),
				lines={detail[1],requirements~="" and ("Requires "..requirements) or nil},
				actions={{caption="Equip",primary=ok,disabled=not ok,reason="Requires "..(requirements:gsub("<[^>]+>","")),fn=function() send("equip",itemId) end}}})
		end
	end
end
-- Hero › Spellbook: every spell with level, element, mana, glyph costs (minus
-- the wielded staff's free elements), damage scaling and the autocast choice.
function Pages.drawSpellbook()
	local CB=UI.CB
	local cs=CB.cs()
	if not Data or not cs or type(Data.SpellOrder)~="table" then dataMissing() return end
	local d=depth()
	if not d then syncing("spellbook") return end
	local lo=CB.loadout()
	local stats=tbl(d.stats)
	local levels=skillsOf(state)
	local magic=num(lo.levels.Magic,nil) or (levels.Magic and levels.Magic.level) or 1
	local weapon=itemDef(lo.weapon)
	local wielding=lo.style=="magic"
	local auto=CB.spell(lo.autocast)
	local maxMana=num(player:GetAttribute("MaxMana"),nil) or num(stats.intelligence,0)
	local mana=num(player:GetAttribute("Mana"),nil) or maxMana
	card({name="SpellbookSummary",motif="Hero",accent=rgb("8FA8FF"),title="Spellbook",titleColor=gold,
		subtitle="Magic "..magic.."  ·  ✦ "..fmt(math.floor(mana)).." / "..fmt(math.floor(maxMana)).." mana",badge=auto and "AUTOCAST" or nil,badgeColor=mint,
		detail=(auto and ("Autocasting "..paint(escape(auto.name),auto.color)..". Attacks with a staff or wand cast it.") or "No autocast: staff and wand attacks cast your strongest unlocked spell.")..
			" Spell bar: keys 1-6, tap, or DPad + L1; right-click a damage spell to autocast it.",
		lines={wielding and weapon and (CB.itemLines(weapon)[2] or nil) or paint("Damage spells and Rootbind need a staff or wand; Mend and Hubward work with any weapon.","A9BDC1")},
		actions=auto and {{caption="Clear",fn=function() send("autocast","none") end}} or nil})
	local function spellCard(spell)
		local locked=magic<num(spell.level,1)
		local element=spell.element and tbl(cs.elements)[spell.element]
		local kindText=spell.kind=="damage" and ((spell.element or "").." element  ·  "..(spell.tier or "").." tier") or ({snare="Snare",heal="Heal",teleport="Teleport"})[spell.kind] or spell.kind
		local lines={}
		local costs={}
		for _,c in ipairs(CB.costs(spell,wielding and weapon or nil)) do
			local have=num(lo.supplies[c.id],count("items",c.id))
			table.insert(costs,c.free and paint(c.n.." "..escape(itemName(c.id)).." (free from staff)","9EE7D2")
				or paint(c.n.." "..escape(itemName(c.id)),have>=c.n and itemHex(c.id) or "E8806A")..paint(" ("..fmt(have)..")","A9BDC1"))
		end
		table.insert(lines,paint("✦ "..num(spell.mana,0).." mana","9FC3FF").."  ·  "..(#costs>0 and table.concat(costs,"  +  ") or "no glyphs"))
		if spell.kind=="damage" then
			local now=CB.spellDamage(spell,stats,wielding and weapon or nil,magic)
			table.insert(lines,"Damage "..fmt(num(spell.damage,0)).." + weapon power, × (1 + Intelligence/100 × "..num(spell.scaling,0)..")"..(now and ("  ·  now ≈ "..paint(fmt(now),"FFD24A")) or ""))
		elseif spell.kind=="snare" then
			table.insert(lines,"Roots a creature for "..num(spell.duration,5).."s (bosses are immune)  ·  "..num(spell.cooldown,0).."s cooldown")
		elseif spell.kind=="heal" then
			table.insert(lines,"Restores "..num(spell.heal,0).."% of your max health  ·  "..num(spell.cooldown,0).."s cooldown  ·  any weapon")
		elseif spell.kind=="teleport" then
			table.insert(lines,"Breaks a Hubward Tablet to return to Compass Quay  ·  not within "..num(cs.combatLock,5).."s of being struck")
		end
		table.insert(lines,paint("+"..fmt(num(spell.xp,0)).." Magic XP per cast","F9CC77")..(spell.requiresWeapon and "  ·  needs a staff or wand" or ""))
		local actions
		if spell.autocast then
			if auto and auto.id==spell.id then
				actions={{caption="Clear",fn=function() send("autocast","none") end}}
			else
				actions={{caption="Autocast",primary=not locked,disabled=locked,reason="Requires Magic "..num(spell.level,1)..".",fn=function() send("autocast",spell.id) end}}
			end
		end
		card({name="Spell"..spell.id,icon=function(parent,size) return itemGlyph(parent,{name=spell.name,color=spell.color},size,locked) end,iconSize=compactAtlas and 30 or 38,
			title=escape(spell.name),titleColor=locked and muted or rgb(lighten(spell.color or "C9F2FF",.2)),
			subtitle="Lv "..num(spell.level,1).."  ·  "..escape(kindText)..(element and "" or ""),
			badge=(auto and auto.id==spell.id) and "AUTOCAST" or (locked and ("Magic "..num(spell.level,1)) or nil),badgeColor=(auto and auto.id==spell.id) and mint or ember,
			lines=lines,actions=actions})
	end
	for _,tier in ipairs(tbl(cs.spellTiers)) do
		heading(string.upper(tier.name).."S    /    "..string.upper(itemName(tier.catalyst)))
		for _,id in ipairs(Data.SpellOrder) do
			local spell=CB.spell(id)
			if spell and spell.tier==tier.id then spellCard(spell) end
		end
	end
	heading("UTILITY")
	for _,id in ipairs(Data.SpellOrder) do
		local spell=CB.spell(id)
		if spell and spell.kind~="damage" then spellCard(spell) end
	end
end
Pages.drawSkills,Pages.drawGear,Pages.drawEnchant,Pages.drawAccessories,Pages.drawPets=drawSkills,drawGear,drawEnchant,drawAccessories,drawPets
end

------------------------------------------------------------------------------
-- Hero › Reforge (Gear depth): Reforge Anvil rolls, reforge stones, essence
-- stars and tomes. Rules and numbers come from Data.Gear over the snapshot's
-- depth.gear = {reforges, stars, books}; upgrades are bound to the item id.
------------------------------------------------------------------------------
do
local GU={target=nil,last=nil}
UI.Gear=GU
local function rules() return Data and type(Data.Gear)=="table" and Data.Gear or nil end
local function gear() return tbl(tbl(depth()).gear) end
local function rank(rarity) return rarityRank(rarity) end
function GU.rarity(id)
	local G,def=rules(),itemDef(id)
	if not def then return "Common" end
	if not G then return def.rarity end
	local ok,rarity=pcall(G.effectiveRarity,gear(),id)
	return ok and type(rarity)=="string" and rarity or def.rarity
end
function GU.hex(id) return rarityHex(GU.rarity(id)) end
function GU.title(id)
	local G=rules()
	if not G or not itemDef(id) then return escape(itemName(id)) end
	local ok,name=pcall(G.displayName,gear(),id)
	return escape(ok and type(name)=="string" and name or itemName(id))
end
function GU.breakdown(id)
	local G=rules()
	if not G or not itemDef(id) then return nil end
	local ok,b=pcall(G.breakdown,gear(),id)
	return ok and type(b)=="table" and b or nil
end
function GU.upgraded(id)
	local G=rules()
	if not G or not itemDef(id) then return false end
	local ok,yes=pcall(G.isUpgraded,gear(),id)
	return ok and yes==true
end
local function starText(n,max) return paint(string.rep("★",n),"F9CC77")..paint(string.rep("☆",math.max(0,max-n)),"5A6E78") end
-- Rich breakdown lines for an item card (empty when nothing is applied).
function GU.lines(id)
	local G,b=rules(),GU.breakdown(id)
	local lines={}
	if not G or not b then return lines end
	if b.masterwork then table.insert(lines,paint("Masterwork: "..escape(tostring(tbl(itemDef(id)).rarity)).." → "..escape(b.rarity),rarityHex(b.rarity))) end
	if b.reforge then table.insert(lines,paint(escape(G.Reforges[b.reforge].name).." reforge: ","C9974A")..statText(b.reforgeStats)) end
	if b.stars>0 then table.insert(lines,starText(b.stars,G.STAR_MAX).." "..statText(b.starStats)) end
	if b.tempering>0 then table.insert(lines,paint("Tempered "..b.tempering.."/"..G.TEMPERING_MAX..": ","D9822B")..statText(b.tomeStats)) end
	return lines
end
function GU.open(id)
	GU.target=id
	current="Hero"
	sectionOf.Hero="Reforge"
	scroll.CanvasPosition=Vector2.zero
	render()
end
-- "+3 Strength, -1 Crit Chance": difference between two stat maps.
local function diffText(from,to)
	local delta,any={},false
	for k,v in pairs(tbl(to)) do if type(v)=="number" then delta[k]=v end end
	for k,v in pairs(tbl(from)) do if type(v)=="number" then delta[k]=(delta[k] or 0)-v end end
	for k,v in pairs(delta) do
		v=math.floor(v*10+.5)/10
		if v==0 then delta[k]=nil else delta[k]=v;any=true end
	end
	return any and statText(delta) or paint("No change","A9BDC1")
end
local function costPart(have,need,text,hex)
	return paint(fmt(have).."/"..fmt(need),have>=need and "9EE7D2" or "E8806A").." "..text
end
local function coinPart(need)
	return paint(fmt(need).." coins",num(state.coins,0)>=need and "F9CC77" or "E8806A")
end
function Pages.drawReforge()
	local G=rules()
	if not G or type(Data.Items)~="table" then dataMissing() return end
	local d=depth()
	if not d then syncing("reforge anvil") return end
	local candidates={}
	for id,n in pairs(tbl(state.items)) do
		if num(n,0)>0 and G.category(itemDef(id)) then table.insert(candidates,id) end
	end
	table.sort(candidates,function(a,b)
		local ea,eb=equippedSlotOf(a)~=nil or table.find(tbl(d.accessoryBag),a)~=nil,equippedSlotOf(b)~=nil or table.find(tbl(d.accessoryBag),b)~=nil
		if ea~=eb then return ea end
		local ra,rb=rank(itemDef(a).rarity),rank(itemDef(b).rarity)
		if ra~=rb then return ra>rb end
		return itemDef(a).name<itemDef(b).name
	end)
	local essences={}
	for _,essenceId in ipairs(G.Essences) do table.insert(essences,fmt(count("items",essenceId)).." "..escape(itemName(essenceId))) end
	card({name="ReforgeSummary",motif="Workshop",title="Reforge Anvil",titleColor=gold,subtitle=fmt(state.coins).." coins  ·  "..table.concat(essences,"  ·  "),
		detail="Reforge gear for coins or apply a reforge stone, star it with essence and bind Tempering or Masterwork Tomes. Upgrades stay with the item in your journal (every copy shares them) and upgraded gear cannot be auctioned."})
	if #candidates==0 then
		card({motif="Workshop",title="Nothing to upgrade",detail="Forge or find a weapon, armor piece, tool or accessory first."})
		return
	end
	if not table.find(candidates,GU.target) then GU.target=candidates[1] end
	heading("CHOOSE AN ITEM    /    "..#candidates.." PIECES")
	local size=compactAtlas and 54 or 62
	local grid=gridHolder(UDim2.fromOffset(size,size),6)
	for i,id in ipairs(candidates) do
		local on=id==GU.target
		local pick=tile(grid,"Reforge"..id,i,function() GU.target=id;render() end)
		make("UIStroke",pick,{Color=on and gold or slate,Transparency=on and 0 or .4,Thickness=on and 2 or 1})
		local art=itemIcon(pick,id,size-12)
		art.Position=UDim2.fromOffset(6,6)
		if equippedSlotOf(id) then UI.tag(pick,"E") end
		local stars=G.starsOf(gear(),id)
		if stars>0 then
			local mark=label(pick,string.rep("★",stars),0,size-16,full,14,UI.heavy,10,rgb("F9CC77"))
			mark.TextXAlignment=Enum.TextXAlignment.Center
		end
	end
	local id=GU.target
	local def=itemDef(id)
	local category=G.category(def)
	local g=gear()
	local b=G.breakdown(g,id)
	-- Item overview: name with reforge and stars, rarity colour, every layer.
	local lines={}
	if def.stats then table.insert(lines,"Base: "..statText(def.stats)) end
	for _,line in ipairs(GU.lines(id)) do table.insert(lines,line) end
	if next(b.total) then table.insert(lines,paint("Upgrade total: ","F3C66E")..statText(b.total)) else table.insert(lines,paint("No upgrades applied yet.","A9BDC1")) end
	card({name="ReforgeItem",item=id,title=GU.title(id),titleColor=rgb(rarityHex(b.rarity)),
		subtitle=escape(b.rarity.." "..tostring(G.CategoryNames[category] or kindLabel(def)))..(b.masterwork and "  ·  Masterwork" or ""),
		badge=equippedSlotOf(id) and "EQUIPPED" or nil,badgeColor=mint,lines=lines})
	heading(string.upper(def.name).."    /    REFORGE")
	-- Anvil roll: cost preview, pool, last result diff.
	local cost=G.reforgeCost(g,id)
	local pool=G.reforgePool(def)
	local names={}
	for _,reforgeId in ipairs(pool) do
		local r=G.Reforges[reforgeId]
		table.insert(names,reforgeId==b.reforge and paint(escape(r.name),"F3C66E") or escape(r.name))
	end
	local rollLines={"Cost: "..coinPart(cost).."  ·  scales with rarity ("..escape(b.rarity)..")",
		"Possible: "..table.concat(names,", ")}
	if b.reforge then table.insert(rollLines,"Current "..escape(G.Reforges[b.reforge].name)..": "..statText(b.reforgeStats)) end
	local last=GU.last
	if last and last.id==id and last.after==b.reforge and last.after~=last.before then
		table.insert(rollLines,paint("Last roll ","A9BDC1")..escape(last.before and G.Reforges[last.before] and G.Reforges[last.before].name or "None").." → "..escape(G.Reforges[b.reforge].name)..": "
			..diffText(last.before and G.reforgeStats(last.before,b.rarity,G.toolSkill(def)) or EMPTY,b.reforgeStats))
	end
	local affordable=num(state.coins,0)>=cost
	card({name="ReforgeRoll",motif="Workshop",title=b.reforge and "Reroll reforge" or "Roll a reforge",titleColor=rgb("E0B04A"),
		subtitle=#pool.." anvil reforges  ·  never repeats the current one",lines=rollLines,
		actions={{caption="Reforge",primary=affordable,disabled=not affordable,reason="Reforging costs "..fmt(cost).." coins.",fn=function()
			GU.last={id=id,before=b.reforge}
			send("reforge",id)
			GU.last.after=G.reforgeOf(gear(),id)
			render()
		end}}})
	-- Reforge stones that fit this item (owned first).
	local stones={}
	for _,reforgeId in ipairs(G.ReforgeOrder[category] or EMPTY) do
		if G.Reforges[reforgeId].stone and G.reforgeFits(reforgeId,def) then table.insert(stones,reforgeId) end
	end
	table.sort(stones,function(x,y)
		local hx,hy=count("items",G.Reforges[x].stone)>0,count("items",G.Reforges[y].stone)>0
		if hx~=hy then return hx end
		return x<y
	end)
	for _,reforgeId in ipairs(stones) do
		local r=G.Reforges[reforgeId]
		local have=count("items",r.stone)
		local stats=G.reforgeStats(reforgeId,b.rarity,G.toolSkill(def))
		local applied=b.reforge==reforgeId
		local reason=applied and ("Already "..r.name..".") or (have<1 and ("Find a "..itemName(r.stone).." first.")) or (num(state.coins,0)<cost and ("Applying it costs "..fmt(cost).." coins.")) or nil
		card({name="Stone"..reforgeId,item=r.stone,title=escape(r.name).." reforge",titleColor=rgb(itemHex(r.stone)),subtitle=escape(itemName(r.stone)).."  ·  ×"..fmt(have),
			badge=applied and "APPLIED" or nil,badgeColor=mint,
			lines={statText(stats),"Change: "..diffText(b.reforgeStats,stats),"Cost: "..costPart(have,1,escape(itemName(r.stone))).."  ·  "..coinPart(cost)},
			actions={{caption="Apply",primary=reason==nil,disabled=reason~=nil,reason=reason,fn=function() send("reforgeStone",id..":"..r.stone) end}}})
	end
	-- Stars.
	if G.canStar(category) then
		heading("ESSENCE STARS    /    +"..G.starPercent(def).."% BASE STATS EACH")
		local labels={}
		for i=1,G.STAR_MAX do labels[i]="★"..i end
		if b.stars>=G.STAR_MAX then
			card({name="ReforgeStars",motif="Journal",title=starText(b.stars,G.STAR_MAX),badge="MAXED",badgeColor=mint,lines={statText(b.starStats)},
				pips={total=G.STAR_MAX,filled=b.stars,color=rgb("E0B04A"),labels=labels}})
		else
			local sc=G.starCost(def,b.stars+1)
			local have=count("items",sc.essence)
			local reason=(have<sc.amount and ("Star "..(b.stars+1).." needs "..sc.amount.." "..itemName(sc.essence)..".")) or (num(state.coins,0)<sc.coins and ("Star "..(b.stars+1).." costs "..fmt(sc.coins).." coins.")) or nil
			card({name="ReforgeStars",motif="Journal",title=starText(b.stars,G.STAR_MAX),subtitle="Next: star "..(b.stars+1).." of "..G.STAR_MAX..(def.dungeon and "  ·  dungeon gear" or ""),
				lines={"Gain: "..diffText(b.starStats,G.starStats(def,b.stars+1)),"Cost: "..costPart(have,sc.amount,escape(itemName(sc.essence))).."  ·  "..coinPart(sc.coins)},
				pips={total=G.STAR_MAX,filled=b.stars,color=rgb("E0B04A"),labels=labels},
				actions={{caption="Star",primary=reason==nil,disabled=reason~=nil,reason=reason,fn=function() send("star",id) end}}})
		end
	end
	-- Tomes.
	heading("TOMES")
	if G.canTemper(category) then
		local have=count("items","TemperingTome")
		local full=b.tempering>=G.TEMPERING_MAX
		local reason=(full and "This item holds the maximum Tempering Tomes.") or (have<1 and "Find or craft a Tempering Tome first.") or nil
		local labels={}
		for i=1,G.TEMPERING_MAX do labels[i]=tostring(i) end
		card({name="TomeTempering",item="TemperingTome",title="Tempering Tome",titleColor=rgb(itemHex("TemperingTome")),subtitle=b.tempering.."/"..G.TEMPERING_MAX.." bound  ·  ×"..fmt(have).." held",
			lines={"Each: "..statText(G.tomeStats(def,1)),b.tempering>0 and ("Bound: "..statText(b.tomeStats)) or nil},badge=full and "MAXED" or nil,badgeColor=mint,
			pips={total=G.TEMPERING_MAX,filled=b.tempering,color=rgb("D9822B"),labels=labels},
			actions=not full and {{caption="Temper",primary=reason==nil,disabled=reason~=nil,reason=reason,fn=function() send("tome",id..":TemperingTome") end}} or nil})
	end
	local base=tostring(def.rarity)
	local bumped=G.bumpRarity(base)
	local have=count("items","MasterworkTome")
	local mythic=base==bumped
	local reason=(b.masterwork and "Already a masterwork.") or (mythic and "Mythic is the highest rarity.") or (have<1 and "Find a Masterwork Tome first.") or nil
	local preview={}
	if not mythic then
		table.insert(preview,"Rarity: "..paint(escape(base),rarityHex(base)).." → "..paint(escape(bumped),rarityHex(bumped)))
		if b.reforge then
			local skill=G.toolSkill(def)
			table.insert(preview,"Reforge: "..diffText(G.reforgeStats(b.reforge,base,skill),G.reforgeStats(b.reforge,bumped,skill)))
		end
		table.insert(preview,"Anvil cost: "..fmt(G.ReforgeCost[base] or 0).." → "..fmt(G.ReforgeCost[bumped] or 0).." coins")
		if category=="accessory" then
			local before,after=tbl(tbl(Data.Rarity)[base]).power,tbl(tbl(Data.Rarity)[bumped]).power
			table.insert(preview,paint("✧ Magical Power "..tostring(before).." → "..tostring(after),"FFAA00"))
		end
	end
	card({name="TomeMasterwork",item="MasterworkTome",title="Masterwork Tome",titleColor=rgb(itemHex("MasterworkTome")),subtitle=(b.masterwork and "Bound" or "Once per item").."  ·  ×"..fmt(have).." held",
		badge=b.masterwork and "APPLIED" or nil,badgeColor=mint,lines=preview,
		actions=not b.masterwork and {{caption="Bind",primary=reason==nil,disabled=reason~=nil,reason=reason,fn=function() send("tome",id..":MasterworkTome") end}} or nil})
end
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
		for _,line in ipairs(UI.CB.itemLines(def)) do table.insert(lines,line) end
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
				table.insert(actions,{caption=def.category=="food" and "Eat" or "Drink",primary=true,fn=function()
					if send("consume",id) then
						-- [Animation] play the eat/drink gesture (animate.client.lua) after a successful consume.
						local g=ReplicatedStorage:FindFirstChild("IsleGestureLocal")
						if g then g:Fire(def.category=="food" and "eat" or "drink",nil,id) end
					end
				end})
			end
		elseif def.kind=="accessory" then
			local bagged=table.find(tbl(d and d.accessoryBag),id)~=nil
			table.insert(actions,{caption=bagged and "Remove" or "Add",fn=function() send("accessory",id) end})
		elseif def.kind=="pet" then
			table.insert(actions,{caption="Adopt",primary=true,fn=function() send("petAdopt",id) end})
		end
		-- Beaconry (§37): kindle a log where you stand (the server checks the ground).
		if Data and type(Data.Beaconry)=="table" and Data.Beaconry.LogById[id] then
			table.insert(actions,{caption="Kindle",fn=function() send("kindle",id) end})
		end
		if enchantKind(def) then
			table.insert(actions,{caption="Enchant",fn=function() enchantTarget=id;current="Hero";sectionOf.Hero="Enchant";scroll.CanvasPosition=Vector2.zero;render() end})
		end
	elseif legacy then
		table.insert(lines,"Restores up to "..tostring(legacy.healing).." health.")
		table.insert(actions,{caption=tostring(legacy.action or "Use"),fn=function() send("heal",id) end})
	end
	if legacy and num(legacy.readyIn,0)>0 then table.insert(lines,paint("Recovering: ready in "..math.ceil(legacy.readyIn).."s","F9CC77")) end
	-- §29 last-copy rule: the server keeps one copy of an upgraded item (Gear.upgraded).
	local kept=def and (UI.Gear.upgraded(id) or next(tbl(tbl(tbl(depth()).enchants)[id]))~=nil) and 1 or 0
	-- Polish QC M2: equipped or bagged items offer no Sell / Sell… (the server refuses
	-- both, as Theme.itemActions already hides them in the satchel menu).
	local worn=equippedSlotOf(id)~=nil or table.find(tbl(d and d.accessoryBag),id)~=nil
	if def and worn then
		if sellConfirm==id then sellConfirm=nil end
		table.insert(lines,paint("Equipped: unequip it (or take it out of your accessory bag) to sell it.","A9BDC1"))
	elseif def and n<=kept then
		table.insert(lines,paint("Upgraded: your last copy cannot be sold (spare copies can).","A9BDC1"))
	elseif def then
		if sellConfirm==id then
			table.insert(lines,paint("Tap Confirm to sell "..(kept>0 and (fmt(n-kept).." spare"..(n-kept>1 and "s" or "")) or ("all "..fmt(n))).." for "..fmt(num(def.value,0)*(n-kept)).." coins"
				..(kept>0 and " (your upgraded copy is kept)" or "")..".","F9CC77"))
			table.insert(actions,{caption="Confirm",fn=function() sellConfirm=nil;send("sell",id) end})
		else
			table.insert(actions,{caption="Sell",fn=function() sellConfirm=id;render() end})
		end
		-- Polish: sell part of a stack through the §31 quantity picker (sell "<id>:<n>").
		if n-kept>1 then
			table.insert(actions,{caption="Sell…",name="ItemDetailSellQty",fn=function()
				sellConfirm=nil
				UI.pickQuantity({verb="sell",base=id,item=id,name=def.name,unit=num(def.value,0),amount=1,max=n-kept,sell=true})
			end})
		end
	end
	local equipped=equippedSlotOf(id)
	-- Gear depth: "<Reforge> <Item name> ★★★" in the effective rarity colour.
	local upgradable=def and Data and type(Data.Gear)=="table" and Data.Gear.category(def)~=nil
	card({name="ItemDetail",item=id,iconSize=compactAtlas and 42 or 54,title=if def then UI.Gear.title(id) else escape(id),titleColor=rgb(if def then UI.Gear.hex(id) else itemHex(id)),
		subtitle=escape((def and UI.Gear.rarity(id) or "Common").." "..kindLabel(def)).."  ·  ×"..fmt(n),badge=equipped and "EQUIPPED" or nil,badgeColor=mint,
		lines=lines,actions=actions})
	if upgradable then
		local upgrades=UI.Gear.lines(id)
		card({name="ItemUpgrades",motif="Workshop",title="Upgrades",titleColor=gold,subtitle=UI.Gear.upgraded(id) and "Reforge, stars and tomes bound to this item" or "Not upgraded yet",
			lines=#upgrades>0 and upgrades or {paint("Reforge it at the anvil, star it with essence or bind tomes in Hero › Reforge.","A9BDC1")},
			actions={{caption="Reforge",fn=function() UI.Gear.open(id) end}}})
	end
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
			local amount=label(slotTile,short(n),0,0,UDim.new(1,-8),16,UI.heavy,12,ivory)
			amount.Position=UDim2.new(0,0,1,-19)
			amount.TextXAlignment=Enum.TextXAlignment.Right
			amount.TextStrokeTransparency=.2
			amount.TextStrokeColor3=deep
		end
		if equippedSlotOf(id) then UI.tag(slotTile,"E") end
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
local categoryOrder={"Ingots","Tools","Weapons","Armor","Arrowheads","Meals","Feasts","Potions","Glyphs","Tablets","Bows","Fletching","Arrows","Staves","Accessories"}
local stationSkills={Forge="Smithing",Hearth="Cooking",Cauldron="Alchemy",Workbench="Carpentry"}
local stationNotes={Forge="Smelt ingots and forge tools, weapons, armor and arrowheads.",Hearth="Cook seared fish and buff feasts.",Cauldron="Brew timed potions and inscribe spell glyphs and Hubward tablets (Glyphcraft).",Workbench="Craft accessories, fletch bows, shafts and arrows (Fletching) and carve staves and wands (Glyphcraft)."}
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
	-- Bows, staves, wands and arrows: their combat line (style, power, reach, tier).
	local combatLine=UI.CB.itemLines(def)[1]
	if combatLine and (def.kind=="weapon" and def.style or def.ammo) then table.insert(parts,combatLine) end
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
-- Workers page (Workers depth): fleet summary with unique-craft progress, a
-- slot grid (type icon, tier, fuel, storage fill), the selected worker's detail
-- (collect / upgrade / refuel / install / remove) and a type browser (assign
-- or draft unique blueprints). All state lives in WK (200-local limit).
local WK={selected=1,group="Mining",groups={"Mining","Woodcutting","Fishing","Farming","Combat"}}
function WK.costText(cost)
	local parts={}
	for id,n in pairs(tbl(cost)) do table.insert(parts,fmt(n).." "..itemName(id)) end
	table.sort(parts)
	return table.concat(parts," + ")
end
function WK.afford(cost)
	for id,n in pairs(tbl(cost)) do if count("items",id)<num(n,0) then return false,"Needs "..fmt(n).." "..itemName(id).."." end end
	return true
end
function WK.allowed(t,levels)
	if num(t.collectionTier,0)<=0 then return true end
	local lvl=levels[t.skill] and levels[t.skill].level or 1
	if lvl<num(t.level,1) then return false,"Requires "..tostring(t.skill).." "..num(t.level,1).."." end
	local _,tier=collectionInfo(t.output)
	if tier<num(t.collectionTier,1) then return false,"Unlocks at "..itemName(t.output).." collection tier "..numeral(num(t.collectionTier,1)).."." end
	-- Region-exclusive resources need their region unlocked (server Workers.allowed).
	if type(t.region)=="string" then
		for _,r in ipairs(tbl(state.regions)) do
			if type(r)=="table" and r.id==t.region and not r.unlocked then return false,"Requires "..escape(tostring(r.name or t.region)).." unlocked." end
		end
	end
	return true
end
function WK.duration(seconds)
	seconds=math.max(0,math.floor(num(seconds,0)))
	if seconds>=3600 then return (seconds//3600).."h "..((seconds%3600)//60).."m" end
	return (seconds//60).."m "..(seconds%60).."s"
end
function WK.hasUnique(crafted,typeId,tier)
	local mask=num(tbl(crafted)[typeId],0)
	return math.floor(mask/2^(tier-1))%2==1
end
function WK.tile(grid,slot,w,unlocked,size,W)
	local on=WK.selected==slot
	local cell=tile(grid,"WorkerSlot"..slot,slot,function() WK.selected=slot;render() end)
	make("UIStroke",cell,{Color=on and gold or slate,Transparency=on and 0 or .3,Thickness=on and 2 or 1})
	if type(w)=="table" then
		local art=itemIcon(cell,w.output,size)
		art.AnchorPoint=Vector2.new(.5,0)
		art.Position=UDim2.new(.5,0,0,6)
		local head=label(cell,"W"..slot.."  ·  T"..numeral(num(w.tier,1)),0,size+8,full,14,UI.heavy,11,gold)
		head.TextXAlignment=Enum.TextXAlignment.Center
		local fuel=type(w.fuel)=="table" and (w.fuel.permanent and "∞ fuel" or WK.duration(w.fuel.remaining)) or ""
		local sub=label(cell,fmt(num(w.ready,0)).." / "..fmt(num(w.capacity,0))..(fuel~="" and ("  ·  "..fuel) or ""),2,size+22,UDim.new(1,-4),14,bold,10,w.full and ember or muted)
		sub.TextXAlignment=Enum.TextXAlignment.Center
		local bar,fill=UI.meter(cell,"Storage",w.full and ember or mint,6)
		bar.AnchorPoint=Vector2.new(.5,1)
		bar.Position=UDim2.new(.5,0,1,-6)
		bar.Size=UDim2.new(1,-14,0,6)
		UI.setMeter(fill,math.clamp(num(w.ready,0)/math.max(1,num(w.capacity,1)),0,1))
	else
		local locked=slot>unlocked
		local art=motif(cell,"Workshop",size)
		art.AnchorPoint=Vector2.new(.5,0)
		art.Position=UDim2.new(.5,0,0,6)
		art.BackgroundTransparency=.5
		local need=W and W.SlotUniques[slot-W.BASE_SLOTS]
		local head=label(cell,locked and ("SLOT "..slot) or ("BUILD "..slot),0,size+8,full,14,UI.heavy,11,locked and muted or gold)
		head.TextXAlignment=Enum.TextXAlignment.Center
		local sub=label(cell,locked and (need and (need.." uniques") or "Locked") or "Open slot",0,size+22,full,14,bold,11,muted)
		sub.TextXAlignment=Enum.TextXAlignment.Center
	end
end
local function drawWorkers()
	local W=Data and type(Data.Workers)=="table" and Data.Workers or nil
	local workers={}
	for i,w in ipairs(tbl(state.workers)) do if type(w)=="table" then workers[i]=w else break end end
	local info=tbl(state.workerInfo)
	local maxSlots=num(info.maxSlots,W and W.MAX_SLOTS or 3)
	local unlocked=math.clamp(num(info.slots,3),1,maxSlots)
	local uniques=num(info.uniques,0)
	local levels=skillsOf(state)
	heading("ISLAND INDUSTRY    /    "..#workers.." BUILT  ·  "..unlocked.." OF "..maxSlots.." SLOTS")
	-- Fleet summary: collect-all, next build, unique-craft progress.
	local prevAt=0
	if W then for _,need in ipairs(W.SlotUniques) do if need<=uniques then prevAt=need end end end
	local nextAt=num(info.nextAt,nil)
	local stored,coins=0,0
	for _,w in ipairs(workers) do stored+=num(w.ready,0); coins+=num(w.coins,0) end
	local actions={{caption="Collect all",primary=stored>0 or coins>0,name="WorkersCollectAll",fn=function() send("workerClaimAll") end}}
	local nextSlot=#workers+1
	if nextSlot<=maxSlots then
		local cost=info.buildCost or {Timber=5*nextSlot,Ore=3*nextSlot}
		local ok,reason=WK.afford(cost)
		if nextSlot>unlocked then ok,reason=false,"Slot "..nextSlot.." unlocks at "..tostring(nextAt or "?").." unique worker crafts." end
		table.insert(actions,{caption="Build "..nextSlot,primary=ok,disabled=not ok,reason=reason,name="WorkersBuild",fn=function() send("workerBuild",tostring(nextSlot)) end})
	end
	card({name="WorkerFleet",motif="Workshop",title="Worker fleet",titleColor=gold,
		subtitle=fmt(stored).." items waiting"..(coins>0 and ("  ·  "..fmt(coins).." auto-sold coins") or ""),badge=uniques.." UNIQUE",badgeColor=gold,
		detail="Workers gather while you are away (up to 48 hours, never past their storage). Craft unique workers — a new type or tier — to open up to "..maxSlots.." slots.",
		lines={nextSlot<=maxSlots and ("Next worker: "..WK.costText(info.buildCost or {Timber=5*nextSlot,Ore=3*nextSlot})) or "Every slot is built."},
		bar=nextAt and {fraction=math.clamp((uniques-prevAt)/math.max(1,nextAt-prevAt),0,1),color=gold,caption=uniques.." / "..nextAt.." unique crafts → slot "..(unlocked+1)}
			or {fraction=1,color=gold,caption="ALL "..maxSlots.." SLOTS OPEN"},
		actions=actions})
	-- Slot grid.
	local width=contentWidth()
	local columns=width>=600 and 6 or (width>=400 and 4 or 3)
	local size=compactAtlas and 34 or 40
	local grid=gridHolder(UDim2.new(1/columns,-6,0,size+52),6)
	for slot=1,maxSlots do WK.tile(grid,slot,workers[slot],unlocked,size,W) end
	local w=workers[WK.selected]
	if not w then
		WK.selected=math.clamp(WK.selected,1,math.max(1,#workers))
		w=workers[WK.selected]
	end
	if not w then
		card({motif="Workshop",title="No workers yet",detail="Build your first worker for 5 timber and 3 ore. It gathers Copperstone Ore until you change its type."})
		return
	end
	local slotId=tostring(WK.selected)
	heading("WORKER "..WK.selected.."    /    "..string.upper(escape(tostring(w.name or w.resource))))
	-- Detail card: output, pace, fuel, storage.
	local lines={}
	table.insert(lines,paint(string.format("%.1f",num(w.perHour,0)).." / hour","F9CC77").."  ·  one every "..num(w.interval,0).." s  ·  speed "..num(w.speed,100).."%")
	local fuel=type(w.fuel)=="table" and w.fuel or nil
	table.insert(lines,fuel and ("Fuel: "..paint(escape(itemName(fuel.id)),itemHex(fuel.id)).." +"..num(fuel.speed,0).."%  ·  "..(fuel.permanent and "permanent" or (WK.duration(fuel.remaining).." left"))) or "Fuel: none — craft briquettes or catalysts at the Workbench.")
	local storeParts={}
	for id,n in pairs(tbl(w.store)) do table.insert(storeParts,fmt(n).." "..escape(itemName(id))) end
	table.sort(storeParts)
	if #storeParts>0 then table.insert(lines,"Stored: "..table.concat(storeParts,"  ·  ")) end
	if num(w.coins,0)>0 then table.insert(lines,paint(fmt(w.coins).." coins from the Coinchute","FFD166")) end
	if type(w.idle)=="string" then table.insert(lines,paint("Idle: "..escape(w.idle).." Reassign it to resume work.","FF7A3D")) end
	local detailActions={{caption="Collect",primary=num(w.ready,0)>0 or num(w.coins,0)>0,name="WorkerCollect",fn=function() send("workerClaim",slotId) end}}
	if w.upgradeCost then
		local ok,reason=WK.afford(w.upgradeCost)
		table.insert(lines,"Tier "..numeral(num(w.tier,1)+1)..": "..WK.costText(w.upgradeCost))
		table.insert(detailActions,{caption="Upgrade",primary=ok,disabled=not ok,reason=reason,name="WorkerUpgrade",fn=function() send("workerUpgrade",slotId) end})
	end
	-- Refuel with the strongest timed fuel held (or the one burning); a permanent
	-- fuel is never spent by quick-refuel (install it from its part card).
	local bestFuel
	for _,id in ipairs(W and W.FuelOrder or {}) do
		local permanent=W.Fuels[id] and W.Fuels[id].permanent
		if count("items",id)>0 and not permanent and (not fuel or fuel.id==id) and not (fuel and fuel.permanent) then bestFuel=id end
	end
	table.insert(detailActions,{caption="Refuel",primary=bestFuel~=nil,disabled=bestFuel==nil,
		reason=fuel and fuel.permanent and "This worker holds a permanent fuel." or "Craft worker fuel at the Workbench (Worker Parts).",name="WorkerRefuel",
		fn=function() send("workerFuel",slotId..":"..tostring(bestFuel)) end})
	card({name="Worker"..WK.selected,item=w.output,title=escape(tostring(w.name or w.resource)),titleColor=rgb(itemHex(w.output)),
		subtitle="Tier "..numeral(num(w.tier,1)).." / "..numeral(num(w.maxTier,7)).."  ·  "..(w.kind=="combat" and "Combat worker" or "Gatherer").."  ·  slot "..WK.selected,
		badge=type(w.idle)=="string" and "IDLE" or (w.full and "FULL" or (num(w.ready,0)>0 and (fmt(w.ready).." READY") or "WORKING")),badgeColor=(w.full or type(w.idle)=="string") and ember or mint,
		lines=lines,pips={total=num(w.maxTier,7),filled=num(w.tier,1),color=gold},
		bar={fraction=math.clamp(num(w.ready,0)/math.max(1,num(w.capacity,1)),0,1),color=w.full and ember or mint,caption=fmt(num(w.ready,0)).." / "..fmt(num(w.capacity,0)).." storage"},
		actions=detailActions})
	-- Upgrade slots and chest.
	local ups=tbl(w.upgrades)
	local upLines={}
	local removeActions={}
	for i=1,(W and W.UPGRADE_SLOTS or 2) do
		local id=ups[i]
		local def=type(id)=="string" and itemDef(id)
		table.insert(upLines,"Upgrade "..i..": "..(def and (paint(escape(def.name),itemHex(id)).." — "..escape(tostring(W and W.Upgrades[id] and W.Upgrades[id].text or ""))) or "empty"))
		if def then table.insert(removeActions,{caption="Remove "..i,name="WorkerRemove"..i,fn=function() send("workerRemove",slotId..":"..i) end}) end
	end
	table.insert(upLines,"Chest: "..(type(w.chest)=="string" and (escape(itemName(w.chest)).." (+"..fmt(W and W.Chests[w.chest] and W.Chests[w.chest].capacity or 0).." storage)") or "none"))
	if type(w.chest)=="string" then table.insert(removeActions,{caption="Remove chest",name="WorkerRemoveChest",fn=function() send("workerRemove",slotId..":chest") end}) end
	card({name="WorkerUpgrades",motif="Workshop",title="Upgrades & storage",subtitle="Two upgrade slots (one of each kind) and one chest",lines=upLines,actions=#removeActions>0 and removeActions or nil})
	-- Parts and fuel held: install / refuel.
	if W then
		local held={}
		for _,list in ipairs({W.UpgradeOrder,W.ChestOrder,W.FuelOrder}) do
			for _,id in ipairs(list) do if count("items",id)>0 then table.insert(held,id) end end
		end
		for _,id in ipairs(held) do
			local def=itemDef(id)
			local isFuel=W.Fuels[id]~=nil
			local partActions={{caption=isFuel and "Refuel" or "Install",primary=true,name="Part"..id,
				fn=function() send(isFuel and "workerFuel" or "workerInstall",slotId..":"..id) end}}
			if isFuel and not W.Fuels[id].permanent and count("items",id)>=8 then
				table.insert(partActions,{caption="Add 8",name="Part"..id.."Eight",fn=function() send("workerFuel",slotId..":"..id..":8") end})
			end
			card({name="WorkerPart"..id,item=id,title=escape(def and def.name or id),titleColor=rgb(itemHex(id)),subtitle=fmt(count("items",id)).." held",
				detail=escape(def and def.description or ""),actions=partActions})
		end
		if #held==0 then
			card({motif="Workshop",title="No worker parts held",detail="Craft fuel, upgrades and chests at the Workbench under Worker Parts. Condensed forms come from the Compacting patterns or a Bundling Frame."})
		end
	end
	-- Type browser: change type or draft unique blueprints.
	if not W then return end
	heading("WORKER TYPES    /    ASSIGN OR DRAFT UNIQUE CRAFTS")
	sectionBar(WK.groups,WK.group,function(name) WK.group=name;render() end,{small=true,prefix="WorkerGroup"})
	local crafted=tbl(info.crafted)
	for _,t in ipairs(W.Types) do
		local group=if t.kind=="combat" then "Combat" else t.skill
		if group==WK.group then
			local ok,reason=WK.allowed(t,levels)
			local filled=0
			for tier=1,#Data.WorkerTiers do if WK.hasUnique(crafted,t.id,tier) then filled+=1 end end
			local nextTier
			for tier=1,#Data.WorkerTiers do if not WK.hasUnique(crafted,t.id,tier) then nextTier=tier break end end
			local typeActions={}
			if t.id~=w.resource then
				table.insert(typeActions,{caption="Assign",primary=ok,disabled=not ok,reason=reason,name="Assign"..t.id,fn=function() send("workerAssign",slotId..":"..t.id) end})
			end
			local typeLines={(t.kind=="combat" and "Produces " or "Gathers ")..paint(escape(itemName(t.output)),itemHex(t.output)).."  ·  "..(t.speed~=1 and (t.speed.."× slower  ·  ") or "")..num(t.xp,0).." "..t.skill.." XP each"}
			if nextTier then
				local cost=W.blueprintCost(t.id,nextTier)
				local can,why=WK.afford(cost)
				if not ok then can,why=false,reason end
				table.insert(typeLines,"Draft tier "..numeral(nextTier)..": "..WK.costText(cost))
				table.insert(typeActions,{caption="Draft "..numeral(nextTier),primary=can,disabled=not can,reason=why,name="Draft"..t.id,
					fn=function() send("workerBlueprint",t.id..":"..nextTier) end})
			end
			card({name="WorkerType"..t.id,item=t.output,title=escape(t.name),titleColor=rgb(itemHex(t.output)),
				subtitle=t.id==w.resource and "Current type" or (ok and "Unlocked" or escape(reason or "Locked")),
				badge=filled.." / "..#Data.WorkerTiers,badgeColor=filled>0 and gold or muted,lines=typeLines,
				pips={total=#Data.WorkerTiers,filled=filled,color=gold},actions=#typeActions>0 and typeActions or nil})
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
					detail=monster.seaCreature and ("Hooked while fishing at Fishing "..num(monster.fishing,1)..".") or "Defeat this creature to record it.",
					lines={UI.CB.triangle(monster)}})
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
					lines={UI.CB.triangle(monster),"Drops: "..dropText(monster.drops)..(monster.slayer and ("  ·  "..paint(escape(tostring(monster.slayer)).." slayer target","E8806A")) or ""),
						monster.seaCreature and paint("Fishing "..num(monster.fishing,1).."  ·  +"..fmt(num(monster.fishingXp,0)).." Fishing XP  ·  "..(monster.waters and escape(table.concat(monster.waters,", ")).." waters" or "any water"),"9EE7D2") or nil}})
			end
		end
	end
end

Pages.drawSlayer,Pages.drawBestiary=drawSlayer,drawBestiary
end

------------------------------------------------------------------------------
-- Slayer tasks (Slayer team): Hunt › Slayer gains a view bar. Tasks (the Slayer
-- skill, current task, streak and points), Masters (requirements and task
-- lists), Families (reach and the block list), Shop (unlocks, extensions,
-- consumables, titles, visor crafts) and Superiors (the superior log); the
-- Tasks view keeps the boss-line contracts below (shown as line ranks). Reads
-- state.slayerTasks (server SlayerTasks.state) and Data.SlayerTasks; every
-- button sends a validated verb (slayerTask/Skip/Cancel/Block/Unblock/Buy/Title).
------------------------------------------------------------------------------
do
local ST=nil -- Data.SlayerTasks, resolved when the page draws
local view="Tasks"
local confirm=nil -- "cancel" | "skip" awaiting a second press
local VIEWS={"Tasks","Masters","Families","Shop","Superiors"}
local baseSlayer=Pages.drawSlayer
local function familyName(id) local f=ST and ST.FamilyById[id] return f and f.name or tostring(id) end
local function monsterNames(f)
	local names={}
	for _,id in ipairs(tbl(f and f.monsters)) do
		local m=Data.Monsters[id]
		if type(m)=="table" then
			local region=Data.RegionById and Data.RegionById[m.region]
			table.insert(names,escape(m.name)..(region and (" ("..escape(region.name)..")") or (m.seaCreature and " (fished up)" or "")))
		end
	end
	return table.concat(names,", ")
end
-- Every streak milestone, lowest first: "Every 10th task in a row pays x5 points, every 50th x15, ...".
local function streakText()
	local list={}
	for _,s in ipairs(tbl(ST.Streak)) do table.insert(list,1,s) end
	local parts={}
	for i,s in ipairs(list) do table.insert(parts,(i==1 and "Every " or "every ")..s.every.."th"..(i==1 and " task in a row pays x" or " x")..s.mult..(i==1 and " points" or "")) end
	return table.concat(parts,", ")
end
local function drawSummary(st)
	local levels=skillsOf(state)
	local sk=tbl(levels.Slayer)
	local lvl=num(sk.level,num(st.level,1))
	card({name="SlayerTaskSummary",motif="Hunt",accent=rgb("B23A48"),title="Slayer "..lvl,titleColor=rgb(lighten("B23A48",.4)),
		subtitle=fmt(num(st.points,0)).." points  ·  streak "..fmt(num(st.streak,0)).."  ·  "..fmt(num(st.completed,0)).." tasks done",
		badge=paint(fmt(num(st.points,0)).." pts","F3C66E"),
		detail="Kill your task's monsters to train Slayer (Slayer XP ≈ the monster's health ÷ "..ST.HP_PER_XP.."). "..streakText()..".",
		bar=sk.fraction and {fraction=num(sk.fraction,0),color=rgb("B23A48"),caption=sk.maxed and "MAX LEVEL" or (fmt(num(sk.xp,0)).." Slayer XP")} or nil})
end
local function drawTask(st)
	local task=type(st.task)=="table" and st.task or nil
	heading("CURRENT    /    TASK")
	if not task then
		card({name="SlayerTaskNone",motif="Hunt",title="No task",titleColor=muted,subtitle="Visit a Slayer master",
			detail="Choose a master on the Masters view (or speak to one in person). Next task pays x"..num(st.nextMult,1).." points."})
		return
	end
	local f=ST.FamilyById[task.family]
	local m=ST.MasterById[task.master]
	local killed,amount=num(task.killed,0),math.max(1,num(task.amount,1))
	local points=num(st.points,0)
	local skipReason=points<ST.SKIP_COST and ("Needs "..ST.SKIP_COST.." points.") or nil
	local actions
	if confirm=="cancel" then
		actions={{name="SlayerCancelConfirm",caption="Confirm cancel",fn=function() confirm=nil send("slayerCancel") end},{name="SlayerCancelKeep",caption="Keep task",fn=function() confirm=nil render() end}}
	elseif confirm=="skip" and not skipReason then
		actions={{name="SlayerSkipConfirm",caption="Confirm skip (-"..ST.SKIP_COST.." pts)",fn=function() confirm=nil send("slayerSkip") end},{name="SlayerSkipKeep",caption="Keep task",fn=function() confirm=nil render() end}}
	else
		actions={{name="SlayerSkip",caption="Skip ("..ST.SKIP_COST.." pts)",disabled=skipReason~=nil,reason=skipReason,fn=function() confirm="skip" render() end},
			{name="SlayerCancel",caption="Cancel",fn=function() confirm="cancel" render() end}}
	end
	local hex=f and f.color or "B23A48"
	card({name="SlayerTaskCurrent",motif="Hunt",accent=rgb(hex),title=escape(familyName(task.family))..(task.extended and "  ·  extended" or ""),titleColor=rgb(lighten(hex,.4)),
		subtitle="From "..escape(m and m.name or tostring(task.master)),badge=fmt(killed).." / "..fmt(amount),badgeColor=ivory,
		detail="Hunt: "..monsterNames(f),
		bar={fraction=killed/amount,color=rgb(hex),caption=fmt(amount-killed).." left"},
		lines={"Completion: "..fmt(ST.pointsFor(task.master,num(st.streak,0)+1)).." points (x"..num(st.nextMult,1)..") + "..fmt(ST.bountyFor(task.master,{GildedBounty=table.find(tbl(st.unlocks),"GildedBounty")~=nil})).." coins"},
		actions=actions})
	if confirm=="cancel" then para(container(),paint("Cancelling is free but breaks your streak of "..num(st.streak,0)..".","E8806A"),1,muted) end
	if confirm=="skip" and not skipReason then para(container(),paint("Skipping costs "..ST.SKIP_COST.." points and keeps your streak; the master assigns a new task.","F3C66E"),1,muted) end
end
local function drawMasters(st)
	heading("SLAYER    /    MASTERS")
	local hasTask=type(st.task)=="table"
	for _,m in ipairs(ST.Masters) do
		local verdict=tbl(tbl(st.masters)[m.id])
		local ok=verdict.ok==true
		local total=0
		for _,t in ipairs(m.tasks) do total+=t.weight end
		local list={}
		for _,t in ipairs(m.tasks) do
			local fam=tbl(tbl(st.families)[t.family])
			local blocked=table.find(tbl(st.blocked),t.family)~=nil
			table.insert(list,(fam.ok==true and not blocked and check or cross).." "..escape(familyName(t.family)).." "..t.min.."–"..t.max.." ("..math.floor(t.weight/total*100+.5).."%)")
		end
		local reason=hasTask and "Finish, skip or cancel your task first." or (not ok and tostring(verdict.reason or "Unavailable")..".") or nil
		card({name="SlayerMaster"..m.id,motif="Hunt",accent=rgb(m.color),title=escape(m.name),titleColor=rgb(lighten(m.color,.4)),
			subtitle=escape((Data.RegionById[m.region] or {}).name or m.region).."  ·  Combat "..m.combat..(m.slayer>1 and ("  ·  Slayer "..m.slayer) or ""),
			badge=paint(m.points.." pts / task",ok and "F3C66E" or "E8806A"),detail=escape(m.blurb),
			lines={table.concat(list,"   "),"Bounty: "..fmt(m.bounty).." coins per task"},
			actions={{name="SlayerGetTask"..m.id,caption="Get task",primary=reason==nil,disabled=reason~=nil,reason=reason,fn=function() send("slayerTask",m.id) end}}})
	end
end
local function drawFamilies(st)
	local blocked=tbl(st.blocked)
	local slots=num(st.blockSlots,ST.BLOCK_SLOTS)
	heading("FAMILIES    /    BLOCK LIST  "..#blocked.." / "..slots)
	for _,f in ipairs(ST.Families) do
		local verdict=tbl(tbl(st.families)[f.id])
		local isBlocked=table.find(blocked,f.id)~=nil
		local action
		if isBlocked then action={name="SlayerUnblock"..f.id,caption="Unblock",fn=function() send("slayerUnblock",f.id) end}
		else
			local refusal=tbl(st.blockRefusal)[f.id]
			local reason=(#blocked>=slots and "Every block slot is full.") or (num(st.points,0)<ST.BLOCK_COST and ("Needs "..ST.BLOCK_COST.." points."))
				or (refusal~=nil and (escape(tostring(refusal))..".")) or nil
			action={name="SlayerBlock"..f.id,caption="Block ("..ST.BLOCK_COST.." pts)",disabled=reason~=nil,reason=reason,fn=function() send("slayerBlock",f.id) end}
		end
		card({name="SlayerFamily"..f.id,motif="Hunt",accent=rgb(f.color),title=escape(f.name),titleColor=rgb(lighten(f.color,.4)),
			subtitle="Slayer "..f.slayer..(f.sea and "  ·  sea creatures" or ""),
			badge=isBlocked and paint("BLOCKED","E8806A") or (verdict.ok==true and paint("REACHABLE","9EE7D2") or paint(escape(tostring(verdict.reason or "Locked")),"A9BDC1")),
			detail=monsterNames(f),actions={action}})
	end
end
local function drawShop(st)
	local owned={}
	for _,id in ipairs(tbl(st.unlocks)) do owned[id]=true end
	local levels=skillsOf(state)
	local lvls={}
	for skill,info in pairs(levels) do lvls[skill]=num(tbl(info).level,1) end
	heading("POINTS    /    SHOP  ·  "..fmt(num(st.points,0)).." points")
	-- Worn gear (mirrors the server: a craft never consumes an equipped cost item).
	local d=depth()
	local worn={}
	for _,id in pairs(tbl(d and d.equipment)) do worn[id]=true end
	for _,id in ipairs(tbl(d and d.accessoryBag)) do worn[id]=true end
	for _,e in ipairs(ST.Shop) do
		local ok,reason=ST.canBuy(e.id,{points=num(st.points,0),unlocks=owned,levels=lvls,items=tbl(state.items)})
		if ok then
			for id in pairs(e.costs or {}) do
				if worn[id] then ok,reason=false,"Unequip "..itemName(id).." before using it to craft." end
			end
		end
		local have=owned[e.id]==true
		local costs={}
		for id,n in pairs(e.costs or {}) do table.insert(costs,fmt(n).." "..paint(escape(itemName(id)),itemHex(id))) end
		table.sort(costs)
		local actions
		if e.kind=="title" and have then
			local wearing=st.title==e.id
			actions={{name="SlayerWear"..e.id,caption=wearing and "Hide title" or "Wear",fn=function() send("slayerTitle",wearing and "none" or e.id) end}}
		elseif have then
			actions={{name="SlayerBuy"..e.id,caption="Owned",disabled=true,reason="Already unlocked."}}
		else
			actions={{name="SlayerBuy"..e.id,caption=e.kind=="craft" and "Assemble" or "Buy",primary=ok,disabled=not ok,reason=reason,fn=function() send("slayerBuy",e.id) end}}
		end
		card({name="SlayerShop"..e.id,motif="Hunt",title=escape(e.name),titleColor=have and mint or ivory,
			subtitle=({unlock="Unlock",extend="Task extension",consumable="Consumable",title="Cosmetic title",craft="Visorwright"})[e.kind] or e.kind,
			badge=have and paint("OWNED","7FE3CC") or paint(e.cost>0 and (fmt(e.cost).." pts") or "free",num(st.points,0)>=e.cost and "F3C66E" or "E8806A"),
			detail=escape(e.text),lines={#costs>0 and ("Materials: "..table.concat(costs,", ")) or nil},actions=actions})
	end
end
local function drawSuperiors(st)
	local owned=table.find(tbl(st.unlocks),"SuperiorCalling")~=nil
	local log=tbl(st.superiors)
	local total=0
	for _,n in pairs(log) do total+=num(n,0) end
	card({name="SlayerSuperiorSummary",motif="Hunt",title="Superior log",titleColor=gold,subtitle=fmt(total).." superiors slain",
		badge=owned and paint("CALLING","9EE7D2") or paint("LOCKED","E8806A"),
		detail=owned and ("Each task kill has a 1 in "..math.floor(1/ST.SUPERIOR_CHANCE+.5).." chance to raise a superior. Only you can fight it; it withdraws after "..ST.SUPERIOR_LIFETIME.."s.")
			or "Unlock Call of the Superior in the Shop to meet stronger variants with unique loot."})
	heading("SUPERIORS")
	for _,id in ipairs(ST.SuperiorOrder) do
		local def=ST.Superiors[id]
		local n=num(log[id],0)
		if n>0 then
			card({name="SlayerSuperior"..id,motif="Hunt",title=escape(def.name),titleColor=rgb(lighten(def.color,.35)),
				subtitle="Lv "..def.level.."  ·  "..paint(fmt(def.hp).." ❤","FF6B6B").."  ·  "..fmt(ST.killXp(def)).." Slayer XP",badge=fmt(n).." slain",badgeColor=ivory})
		else
			card({name="SlayerSuperior"..id,locked=true,title="???",titleColor=muted,subtitle=escape(familyName(def.family)).." superior  ·  not yet met"})
		end
	end
end
local function drawSlayerTasks()
	ST=Data and type(Data.SlayerTasks)=="table" and Data.SlayerTasks or nil
	if not ST then return baseSlayer() end
	sectionBar(VIEWS,view,function(name) view=name confirm=nil render() end,{small=true,prefix="SlayerView",maxPer=compactAtlas and 3 or 5})
	local st=type(state.slayerTasks)=="table" and state.slayerTasks or nil
	if view=="Tasks" then
		if st then drawSummary(st) drawTask(st) else syncing("slayer tasks") end
		heading("BOSS LINES    /    LINE RANKS")
		para(container(),paint("Boss lines keep their own line ranks (1–9). Each boss slain also trains the Slayer skill.","A9BDC1"),1,muted)
		return baseSlayer()
	end
	if not st then syncing("slayer tasks") return end
	if view=="Masters" then drawMasters(st)
	elseif view=="Families" then drawFamilies(st)
	elseif view=="Shop" then drawShop(st)
	else drawSuperiors(st) end
end
Pages.drawSlayer=drawSlayerTasks
end
-- End Slayer tasks section.

------------------------------------------------------------------------------
-- Hunt › Dungeon: Observatory classes, class levels, floors I–VII, Master Mode,
-- secrets, grading and credit rules (Dungeons / Dungeon Classes teams).
-- Floors are chosen at the in-world daises by the Vault Gate; the class and
-- Master Mode can be set here (verbs dungeonClass, dungeonMaster) or at the pad.
-- The party HUD (right column, under the minimap) lists each delver's class and
-- carries Q / R ability buttons while a run is underway.
------------------------------------------------------------------------------
do
local dungeonUi={violet="8E7CC3"}
local DC=Data and type(Data.DungeonClasses)=="table" and Data.DungeonClasses or nil
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
	if type(m.regen)=="table" then table.insert(out,"Boss regenerates "..math.floor(num(m.regen.fraction,0)*100+.5).."% every "..num(m.regen.every,0).."s while wisps live") end
	if type(m.enrage)=="table" then table.insert(out,"Enrages after "..num(m.enrage.after,0).."s ("..num(m.enrage.damageMult,1).."× damage)") end
	if type(m.overload)=="table" then table.insert(out,"Strikes faster below "..math.floor(num(m.overload.below,0)*100+.5).."% HP") end
	-- Dungeon endgame: cumulative rooms between the prisms and the sentinel hall.
	if type(m.rooms)=="table" and dungeonUi.EG then
		local names={}
		for _,id in ipairs(m.rooms) do table.insert(names,dungeonUi.EG.RoomNames[id] or tostring(id)) end
		table.insert(out,"Rooms: "..table.concat(names," → "))
	end
	return #out>0 and table.concat(out,"  ·  ") or "The original three-prism encounter"
end
-- Dungeon endgame (Data.DungeonEndgame): gear-score gates, Master Mode I–VII lock
-- reasons, boss phases, bonus chest, run log / weekly bests and the Essence page.
dungeonUi.EG=Data and type(Data.DungeonEndgame)=="table" and Data.DungeonEndgame or nil
function dungeonUi.endgame() return tbl(tbl(state).dungeonEndgame) end
function dungeonUi.mode(index,master) return (master and "Master " or "")..numeral(index) end
-- nil when open, else the first unmet requirement.
function dungeonUi.lock(index,master,level,gearScore,best)
	local f=Data.DungeonFloors[index]
	if type(f)~="table" then return "Unknown floor" end
	if level<num(f.level,1) then return "Needs Dungeoneering "..num(f.level,1) end
	if master and not (DC and DC.masterUnlocked(index,best)) then return "Needs a grade "..(DC and DC.MASTER_UNLOCK_GRADE or "S").." clear of the floor" end
	local EG=dungeonUi.EG
	local gate=EG and EG.gearGate(index,master) or 0
	if gearScore<gate then return "Needs gear score "..gate.." (yours "..math.floor(gearScore)..")" end
	return nil
end
function dungeonUi.phaseLines(index)
	local EG=dungeonUi.EG
	local b=EG and EG.Bosses[index]
	if not b then return nil end
	local parts={}
	for _,ph in ipairs(b.phases) do
		local mechs={}
		for _,kind in ipairs({"verdict","blight","nova"}) do
			local m=EG.Mechanics[kind]
			if ph.every[kind] then table.insert(mechs,m.glyph.." "..m.name.." ("..m.role..")") end
		end
		if ph.lock then table.insert(mechs,EG.Mechanics.lock.glyph.." "..EG.Mechanics.lock.name.." (Puzzle)") end
		table.insert(parts,paint(escape(ph.name),"F2A48F").." ≤"..math.floor(ph.below*100+.5).."%: "..table.concat(mechs,", "))
	end
	return "Phases: "..table.concat(parts,"  ·  ")
end
function dungeonUi.time(seconds)
	seconds=math.max(0,math.floor(num(seconds,0)))
	return (seconds//60)..":"..string.format("%02d",seconds%60)
end
function dungeonUi.itemsText(items)
	local parts={}
	for id,n in pairs(tbl(items)) do
		if type(id)=="string" then table.insert(parts,{id=id,text=paint(escape(itemName(id)),itemHex(id)).." ×"..num(n,0)}) end
	end
	table.sort(parts,function(a,b) return a.id<b.id end)
	local out={}
	for _,x in ipairs(parts) do table.insert(out,x.text) end
	return #out>0 and table.concat(out,", ") or "Nothing but dust"
end
function dungeonUi.drawEndgame(eview)
	local EG=dungeonUi.EG
	if not EG then return end
	heading("ENDGAME")
	-- Bonus chest (contents fixed at the clear; opening only reveals what was rolled).
	local chest=eview.chest
	local coins=num(tbl(state).coins,0)
	local keys=num(eview.keys,0)
	if type(chest)=="table" then
		local cost=num(chest.cost,0)
		card({name="DungeonBonusChest",motif="Hunt",accent=gold,edge=gold,title="Bonus chest  ·  Floor "..dungeonUi.mode(num(chest.floor,1),chest.master==true).."  ·  grade "..escape(tostring(chest.grade or "?")),titleColor=gold,
			subtitle="Waiting "..clock(num(chest.expiresIn,0)).."  ·  "..fmt(cost).." coins or a Lodestar Key",badge="🗝 ×"..keys,badgeColor=ivory,
			detail="Rolled once when the boss fell and saved to your journal: leaving, rejoining or waiting never changes it. The fee is "..math.floor(EG.CHEST_FEE_SHARE*100+.5).."% of what you see inside (minimum "..fmt(EG.bonusCost(num(chest.floor,1),chest.master==true)).."), so you always know what you pay for.",
			lines={"Inside: "..dungeonUi.itemsText(chest.items)},
			actions={{caption="Open · "..fmt(cost).." coins",primary=coins>=cost,name="DungeonChestOpen",disabled=coins<cost,reason="Not enough coins.",fn=function() send("dungeonChest","open") end},
				{caption="Use key ("..keys..")",name="DungeonChestKey",disabled=keys<1,reason="No Lodestar Key.",fn=function() send("dungeonChest","key") end},
				{caption="Leave sealed",name="DungeonChestSkip",fn=function() send("dungeonChest","skip") end}}})
	else
		card({name="DungeonBonusChest",motif="Hunt",title="Bonus chest",titleColor=ivory,subtitle="None waiting  ·  🗝 Lodestar Keys ×"..keys,
			detail="Every credited clear rolls one bonus chest (floor chest at ×"..EG.BONUS_CHANCE.." chance plus essence). Open it for coins or a Lodestar Key within "..clock(EG.CHEST_SECONDS)..", or leave it sealed.",
			lines={"Fee: "..math.floor(EG.CHEST_FEE_SHARE*100+.5).."% of the shown contents' value, at least "..table.concat((function() local t={} for i=1,#Data.DungeonFloors do table.insert(t,numeral(i).." "..short(EG.bonusCost(i,false)).."/"..short(EG.bonusCost(i,true))) end return t end)(),"  ·  ").." (normal / Master)"}})
	end
	-- Weekly bests and the weekly first-clear bounty.
	local week=tbl(eview.week)
	local best,bounty=tbl(week.best),tbl(week.bounty)
	local weekLines={}
	for i=1,#Data.DungeonFloors do
		local row={}
		for _,master in ipairs({false,true}) do
			if not master or (DC and i<=DC.MASTER_FLOORS) then
				local key=EG.key(i,master)
				local score=best[key]
				table.insert(row,dungeonUi.mode(i,master)..": "..(score and (num(score,0).." ("..Data.dungeonGrade(num(score,0))..")") or "—")
					..(bounty[key] and "" or paint(" +"..EG.bounty(i,master).."✦","9EE7D2")))
			end
		end
		table.insert(weekLines,table.concat(row,"   "))
	end
	card({name="DungeonWeekly",motif="Hunt",title="This week",titleColor=gold,subtitle="Resets in "..clock(num(week.resetIn,0)).."  ·  ✦ = weekly first-clear essence still available",lines=weekLines})
	-- Run log and personal bests.
	local logLines={}
	for _,e in ipairs(tbl(eview.log)) do
		if type(e)=="table" then
			table.insert(logLines,"Floor "..dungeonUi.mode(num(e.f,1),e.m==true).."  ·  "..paint(escape(tostring(e.g or "?")),"F9CC77").." "..num(e.s,0).."  ·  "..dungeonUi.time(e.sec).."  ·  "..num(e.d,0)..(num(e.d,0)==1 and " fall" or " falls"))
		end
	end
	if #logLines==0 then logLines={"No credited clears yet."} end
	local pbParts={}
	for i=1,#Data.DungeonFloors do
		for _,master in ipairs({false,true}) do
			local pb=tbl(eview.pb)[EG.key(i,master)]
			if type(pb)=="table" then table.insert(pbParts,dungeonUi.mode(i,master).." "..num(pb.score,0).." in "..dungeonUi.time(pb.seconds)) end
		end
	end
	table.insert(logLines,1,paint("Personal bests: ","9EE7D2")..(#pbParts>0 and table.concat(pbParts,"  ·  ") or "none yet"))
	card({name="DungeonRunLog",motif="Hunt",title="Run log",titleColor=ivory,subtitle="Last "..EG.LOG_LIMIT.." credited clears, newest first",lines=logLines})
end
-- Class rows from the snapshot (server Classes.state), or level 1 defaults.
function dungeonUi.view()
	local view=tbl(tbl(state).dungeonClasses)
	return view,tbl(view.classes),tbl(view.floors)
end
function dungeonUi.classRow(rows,id)
	local row=rows[id]
	if type(row)=="table" then return row end
	return {level=1,xp=0,floor=0,ceiling=DC and DC.xpForLevel(2) or 1,fraction=0,maxed=false}
end
function dungeonUi.pct(x) return math.floor(num(x,0)*1000+.5)/10 .."%" end
local function drawDungeon()
	if not Data or type(Data.DungeonFloors)~="table" or type(Data.Dungeons)~="table" then dataMissing() return end
	local levels=skillsOf(state)
	local level=levels.Dungeoneering and levels.Dungeoneering.level or 1
	local rules=Data.Dungeons
	local result=player:GetAttribute("DungeonResult")
	local notice=player:GetAttribute("ExpeditionNotice")
	local chosen=num(player:GetAttribute("ExpeditionFloor"),1)
	local view,rows,floorRows=dungeonUi.view()
	local selectedClass=view.selected
	if type(selectedClass)~="string" or not (DC and DC.valid(selectedClass)) then selectedClass=nil end
	local inRun=player:GetAttribute("DungeonInRun")==true
	local classText=selectedClass and (DC.defs[selectedClass].glyph.." "..DC.defs[selectedClass].name.." "..num(dungeonUi.classRow(rows,selectedClass).level,1)) or "Unclassed"
	local eview=dungeonUi.endgame()
	local gearScore=num(eview.gearScore,0)
	card({name="DungeonSummary",motif="Hunt",accent=rgb(dungeonUi.violet),title="The Hollow Observatory",titleColor=rgb(lighten(dungeonUi.violet,.35)),
		subtitle="Dungeoneering "..level.."  ·  Gear score "..math.floor(gearScore).."  ·  Selected: Floor "..numeral(chosen).."  ·  "..classText..(view.master==true and "  ·  "..paint("Master Mode","E8806A") or ""),badge="Party ≤ "..num(rules.maxParty,5),badgeColor=ivory,
		detail="Choose a class at the oath pedestals or below, a floor at the daises beside the Vault Gate, open the run at the gate, then stand on the matchmaking pad within "..num(rules.padSeconds,10).."s to join.",
		lines={type(result)=="string" and result~="" and ("Last clear: "..escape(result)) or nil,
			type(notice)=="string" and notice~="" and paint(escape(notice),"F9CC77") or nil,
			inRun and paint("In a run: class and Master Mode are locked until it ends. Class ability: Q · Ultimate: R (keys at the core, or the party HUD buttons).","9EE7D2") or nil}})
	if DC then
		heading("CLASSES")
		for _,id in ipairs(DC.order) do
			local def=DC.defs[id]
			local row=dungeonUi.classRow(rows,id)
			local lvl=num(row.level,1)
			local ms=DC.milestoneState(lvl)
			local bonus=DC.levelBonus(id,lvl)
			local nextMilestone
			for _,m in ipairs(DC.milestones) do if lvl<m.level then nextMilestone=m break end end
			local isSelected=selectedClass==id
			local boosts={"+"..dungeonUi.pct(bonus.damage).." damage"}
			if bonus.mitigation>0 or def.attack.mitigation then table.insert(boosts,dungeonUi.pct((def.attack.mitigation or 0)+bonus.mitigation).." damage reduction") end
			if bonus.healing>0 then table.insert(boosts,"+"..dungeonUi.pct(bonus.healing).." healing") end
			local actions
			if isSelected then
				actions={{caption="Go unclassed",name="DungeonClassNone",disabled=inRun,reason="Locked during a run.",fn=function() send("dungeonClass","none") end}}
			else
				actions={{caption="Choose",primary=not inRun,name="DungeonClass"..id,disabled=inRun,reason="Locked during a run.",fn=function() send("dungeonClass",id) end}}
			end
			card({name="DungeonClass_"..id,motif="Hunt",accent=rgb(def.color),edge=isSelected and rgb(def.color) or nil,
				title=def.glyph.."  "..escape(def.name).."  ·  "..escape(def.role),titleColor=rgb(lighten(def.color,.3)),
				subtitle="Class level "..lvl.." / "..DC.MAX_LEVEL..(ms.title and "  ·  "..paint("Paragon","F9CC77") or ""),
				badge=isSelected and (check.." Selected") or ("Lv "..lvl),badgeColor=ivory,
				detail=escape(def.passive),
				bar={fraction=num(row.fraction,0),color=rgb(def.color),caption=row.maxed and "CLASS MAXED" or (fmt(num(row.xp,0)).." / "..fmt(num(row.ceiling,0)).." XP to level "..(lvl+1))},
				lines={paint("Q · "..escape(def.ability.name),"F9CC77").."  ("..math.floor(DC.cooldown(id,lvl)+.5).."s"..(ms.empowered and ", empowered" or "")..")  "..escape(def.ability.text),
					paint("R · "..escape(def.ultimate.name),"E8806A").."  ("..ms.charges.."× per run)  "..escape(def.ultimate.text),
					"Dungeon-only boosts: "..table.concat(boosts,"  ·  "),
					"Bonus feat: "..escape(def.feat.text).."  ·  Class weapon: "..paint(escape(itemName(def.weapon)),itemHex(def.weapon)),
					nextMilestone and ("Next at level "..nextMilestone.level..": "..escape(nextMilestone.text)) or paint("Every milestone unlocked","9EE7D2")},
				actions=actions})
		end
		card({name="DungeonTeam",motif="Hunt",title="Team composition",titleColor=gold,subtitle="Duplicates allowed · unique classes pay more",
			lines={"Class XP ×(1 + "..math.floor(DC.TEAM_STEP*100+.5).."% per unique class beyond the first), up to ×"..UI.dec(1+DC.TEAM_STEP*(#DC.order-1))..".",
				"A balanced party (3+ delvers, every class different) adds +5 to the Bonus score.",
				"Class XP = floor Dungeoneering XP × 0.75 × grade × team (× Master Mode XP: "..UI.dec(DC.MASTER_XP).." on Floor I to "..UI.dec(DC.masterScale(DC.MASTER_FLOORS).xp).." on Floor "..numeral(DC.MASTER_FLOORS).."), paid to your selected class only."}})
		-- Master Mode toggle (unlocked per floor by a grade S clear; Dungeon endgame: floors I–VII).
		local anyMaster=false
		for i=1,DC.MASTER_FLOORS do if tbl(floorRows[i]).masterUnlocked==true then anyMaster=true end end
		local masterOn=view.master==true
		local top=DC.masterScale(DC.MASTER_FLOORS)
		local EGm=dungeonUi.EG
		card({name="DungeonMaster",motif="Hunt",accent=rgb("E8806A"),title="Master Mode",titleColor=rgb("F2A48F"),
			subtitle="Floors I–"..numeral(DC.MASTER_FLOORS).."  ·  tougher bosses, richer chests",badge=masterOn and "ON" or "OFF",badgeColor=ivory,
			detail="Unlocks per floor after a grade "..DC.MASTER_UNLOCK_GRADE.." (or better) clear. Runs you open use your setting; every delver must have the floor's Master Mode unlocked and its Master gear score.",
			lines={"×"..UI.dec(DC.MASTER_MULT).."–"..UI.dec(top.hp).." HP  ·  ×"..UI.dec(DC.MASTER_MULT).."–"..UI.dec(top.damage).." damage  ·  par ×"..UI.dec(DC.MASTER_PAR).."–"..UI.dec(top.par).."  ·  +"..DC.MASTER_ROLLS.." chest roll  ·  ×"..UI.dec(DC.MASTER_XP).."–"..UI.dec(top.xp).." XP and coins",
				EGm and ("Master rewards: ×"..EGm.MASTER_ESSENCE.." essence · +"..DC.MASTER_SCORE_BONUS.." Bonus score cap · mechanics hit "..math.floor(EGm.MASTER_MECH*100+.5).."% harder · Master-only drops: "
				..paint(escape(itemName("EclipsedStarcore")),itemHex("EclipsedStarcore"))..", "..paint(escape(itemName("SovereignHalo")),itemHex("SovereignHalo"))..", "..paint(escape(itemName("Thronebreaker")),itemHex("Thronebreaker"))) or nil},
			actions={{caption=masterOn and "Turn off" or "Turn on",primary=not masterOn and anyMaster,name="DungeonMasterToggle",disabled=(not masterOn and not anyMaster) or inRun,
				reason=inRun and "Locked during a run." or "Clear a floor at grade "..DC.MASTER_UNLOCK_GRADE.." first.",fn=function() send("dungeonMaster",masterOn and "off" or "on") end}}})
	end
	heading("FLOORS")
	for index,f in ipairs(Data.DungeonFloors) do
		if type(f)=="table" then
			local need=num(f.level,1)
			local open=level>=need
			local boss=tbl(f.boss)
			local rw=tbl(f.rewards)
			local fr=tbl(floorRows[index])
			local total=DC and DC.secretCount(index) or 0
			local found=num(fr.secrets,0)
			local masterLine=nil
			if DC and index<=DC.MASTER_FLOORS then
				local mBest=num(fr.masterBest,0)
				local mLock=dungeonUi.lock(index,true,level,gearScore,num(fr.best,0))
				masterLine=fr.masterUnlocked==true and (paint("Master Mode unlocked","E8806A").."  ·  par "..math.floor(DC.par(index,true)+.5).."s"
					..(mBest>0 and ("  ·  Master best "..mBest.." ("..Data.dungeonGrade(mBest)..")  ·  clears "..num(fr.masterClears,0)) or "  ·  no Master clear yet")
					..(mLock and paint("  ·  "..cross.." "..mLock,"F9CC77") or ""))
					or ("Master Mode: clear at grade "..DC.MASTER_UNLOCK_GRADE.." to unlock")
			end
			local lockText=dungeonUi.lock(index,false,level,gearScore,num(fr.best,0))
			local gate=dungeonUi.EG and dungeonUi.EG.gearGate(index,false) or 0
			card({name="DungeonFloor"..index,motif="Hunt",locked=not open,accent=open and rgb(dungeonUi.violet) or nil,
				title=escape(f.name or ("Floor "..index)).."  ·  "..escape(f.subtitle or ""),titleColor=open and ivory or muted,
				subtitle="Boss: "..escape(boss.name or "?").."  ·  "..paint(escape(boss.attack or ""),"E8806A"),
				badge=(open and check or cross).." Dungeoneering "..need,badgeColor=ivory,
				detail=dungeonUi.mechanics(f.mechanics),
				pips=total>0 and {total=total,filled=math.clamp(found,0,total),color=gold} or nil,
				lines={lockText and paint(cross.." Locked: "..lockText,"F9CC77") or (gate>0 and paint(check.." Gear score "..gate.." met","9EE7D2") or nil),
					dungeonUi.phaseLines(index),
					"Grade B reward: "..fmt(rw.dungeoneeringXp).." Dungeoneering XP  ·  "..fmt(rw.combatXp).." Combat XP  ·  "..fmt(rw.coins).." coins  ·  "..num(rw.stormglass,0).." Stormglass",
					"Chest: "..dungeonUi.drops(f.chest),
					total>0 and ("Secrets: best "..found.." / "..total.."  ·  clears "..num(fr.clears,0)..(num(fr.best,0)>0 and ("  ·  best score "..num(fr.best,0)) or "")) or nil,
					masterLine}})
		end
	end
	dungeonUi.drawEndgame(eview)
	heading("SCORE & GRADE")
	local grades={}
	for _,g in ipairs(tbl(Data.DungeonGrades)) do
		if type(g)=="table" then table.insert(grades,paint(escape(g.grade),"F9CC77").." ≥"..num(g.min,0).." ×"..num(g.mult,1)) end
	end
	card({name="DungeonGrades",motif="Hunt",title="Score = (speed + survival + puzzle + secrets) × 0.75 + bonus",titleColor=gold,subtitle="Each part 0–100 · bonus ≤ "..(DC and DC.BONUS_CAP or 20).." · total 300",
		detail="Speed is full until the floor's par time and reaches 0 at twice par. Each death costs 20 survival; each wrong prism, lit mirror turned, wrong glyph or unbroken Eventide Nova costs 15 puzzle. Secrets: hidden caches and levers (2–5 per floor). Bonus: 3 per class feat, +5 for a balanced party (+5 more cap in Master Mode).",
		lines={table.concat(grades,"   "),"Higher grades multiply XP, coins and essence, add Stormglass at S/S+, and boost the chest's rare roll (Magic Find applies too). Each secret adds 1 essence and 5% coins."}})
	card({name="DungeonRules",motif="Hunt",title="Fair credit",titleColor=ivory,
		lines={"Contribute at least "..math.floor(num(rules.contributionShare,0.1)*100).."% of the party's damage and tuning to open the chest"..(dungeonUi.EG and (" (and, in parties of 3+, "..math.floor(dungeonUi.EG.MEDIAN_SHARE*100).."% of the median delver's), acting within the last "..dungeonUi.EG.RECENT_SECONDS.."s before the boss falls.") or "."),
			dungeonUi.EG and ("Dropped out? Rejoin within "..dungeonUi.EG.REJOIN_SECONDS.."s to keep your place and contribution. Each run is credited once.") or nil,
			"Chest cooldown: "..num(rules.clearCooldown,90).."s between credited clears.",
			"Ironman journals are credited on solo clears or with "..math.floor(num(rules.ironmanDamageShare,0.3)*100).."% of the party's damage."}})
end
Pages.drawDungeon=drawDungeon
-- Hunt › Essence (Dungeon endgame): Observatory Essence, Eclipsed Starcores and
-- Lodestar Keys; regular stars (verb star) and Master stars (verb masterStar)
-- for owned Observatory gear; the Essence Exchange (verb essenceBuy).
local function drawEssence()
	local EG=dungeonUi.EG
	local G=Data and Data.Gear
	if not EG or not G then dataMissing() return end
	local eview=dungeonUi.endgame()
	local items=tbl(tbl(state).items)
	local gear=tbl(tbl(tbl(state).depth).gear)
	local coins=num(tbl(state).coins,0)
	local essence=num(items.ObservatoryEssence,0)
	local cores=num(items.EclipsedStarcore,0)
	card({name="EssenceSummary",motif="Hunt",accent=rgb(dungeonUi.violet),item="ObservatoryEssence",title="Observatory Essence",titleColor=rgb(lighten(dungeonUi.violet,.35)),
		subtitle=fmt(essence).." essence  ·  "..fmt(cores).." Eclipsed Starcores  ·  "..fmt(num(items.LodestarKey,0)).." Lodestar Keys",badge="Gear score "..math.floor(num(eview.gearScore,0)),badgeColor=ivory,
		detail="Every Observatory clear pays essence (more for grades, secrets and Master Mode, plus a weekly first-clear bounty per floor). Stars ★ add "..G.DUNGEON_STAR_PERCENT.."% of a dungeon item's base stats each; once an item has "..G.STAR_MAX.." stars, Master stars ✪ add another "..(EG.MASTER_STAR_PERCENT or G.DUNGEON_STAR_PERCENT).."% each (up to "..EG.MASTER_STAR_MAX..") with Eclipsed Starcores from Master Mode chests."})
	heading("ESSENCE EXCHANGE")
	for _,e in ipairs(EG.Exchange) do
		card({name="EssenceBuy_"..e.id,motif="Hunt",item=e.id,title=paint(escape(itemName(e.id)),itemHex(e.id)),subtitle=e.essence.." Observatory Essence"..(e.coins>0 and (" + "..fmt(e.coins).." coins") or ""),
			detail=escape(e.text),actions={{caption="Exchange",primary=essence>=e.essence,name="EssenceBuy"..e.id,disabled=essence<e.essence or coins<e.coins,reason="Not enough essence.",fn=function() send("essenceBuy",e.id) end}}})
	end
	heading("OBSERVATORY GEAR")
	local owned={}
	for id,n in pairs(items) do
		local def=type(id)=="string" and Data.Items[id]
		if def and num(n,0)>0 and EG.canMasterStar(def) then table.insert(owned,id) end
	end
	table.sort(owned,function(a,b)
		local ra,rb=Data.Rarity[Data.Items[a].rarity].rank,Data.Rarity[Data.Items[b].rarity].rank
		if ra~=rb then return ra>rb end
		return a<b
	end)
	if #owned==0 then
		card({name="EssenceNoGear",motif="Hunt",title="No Observatory gear yet",titleColor=muted,detail="Observatory chests drop weapons and armor that take stars and Master stars here."})
	end
	for _,id in ipairs(owned) do
		local def=Data.Items[id]
		local b=G.breakdown(gear,id)
		local stars,mstars=num(b.stars,0),num(b.masterStars,0)
		local starLine=paint(string.rep("★",stars),"F9CC77")..paint(string.rep("☆",G.STAR_MAX-stars),"5A6E78").."  "..paint(string.rep("✪",mstars),"E8806A")..paint(string.rep("✪",EG.MASTER_STAR_MAX-mstars),"3E4A52")
		local action,costLine
		if stars<G.STAR_MAX then
			local c=G.starCost(def,stars+1)
			costLine="Star "..(stars+1)..": "..c.amount.." "..escape(itemName(c.essence)).." + "..fmt(c.coins).." coins"
			action={caption="Star "..(stars+1),primary=true,name="EssenceStar_"..id,disabled=num(items[c.essence],0)<c.amount or coins<c.coins,reason="Not enough essence or coins.",fn=function() send("star",id) end}
		elseif mstars<EG.MASTER_STAR_MAX then
			local c=EG.masterStarCost(def,mstars+1)
			costLine="Master star "..(mstars+1)..": "..c.amount.." essence + "..c.cores.." Eclipsed Starcore"..(c.cores>1 and "s" or "").." + "..fmt(c.coins).." coins"
			action={caption="Master star "..(mstars+1),primary=true,name="EssenceMasterStar_"..id,disabled=essence<c.amount or cores<c.cores or coins<c.coins,reason="Not enough essence, Starcores or coins.",fn=function() send("masterStar",id) end}
		else
			costLine=paint("Every star and Master star forged","9EE7D2")
		end
		local bonus={}
		for stat,v in pairs(tbl(b.starStats)) do bonus[stat]=(bonus[stat] or 0)+v end
		for stat,v in pairs(tbl(b.masterStarsStats)) do bonus[stat]=(bonus[stat] or 0)+v end
		local parts={}
		for stat,v in pairs(bonus) do table.insert(parts,"+"..fmt(v).." "..stat) end
		table.sort(parts)
		card({name="EssenceGear_"..id,motif="Hunt",item=id,title=paint(escape(def.name),itemHex(id)),subtitle=starLine,badge="score "..EG.itemScore(gear,id),badgeColor=ivory,
			lines={costLine,#parts>0 and ("Star bonus: "..table.concat(parts,", ")) or nil},actions=action and {action} or nil})
	end
end
Pages.drawEssence=drawEssence
-- Party HUD: DungeonParty = "Name|Class|Level;..." plus this delver's Q / R
-- ability buttons (touch and click; Q / R on the keyboard are the heart's own
-- prompt keys, so the buttons never double-fire a keypress). Placed in the right
-- column under the Wayfinder minimap (nav.client.lua: y 8, SIZE 118 on short
-- screens / 156, + 34 controls), clear of the toast lane; short screens use a
-- 100 px column right of the Attack button (glyph + level roster).
do
	local hudFrame=make("TextButton",gui,{Name="DungeonPartyHud",Text="",AutoButtonColor=false,BackgroundColor3=deep,BackgroundTransparency=.06,BorderSizePixel=0,
		AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-10,0,204),Size=UDim2.fromOffset(220,46),Visible=false,Selectable=false})
	rounded(hudFrame,12,UI.brass)
	local title=label(hudFrame,"OBSERVATORY PARTY",12,4,UDim.new(1,-24),16,UI.heavy,11,rgb(lighten(dungeonUi.violet,.35)))
	title.Name="Title"
	local list=label(hudFrame,"",12,20,UDim.new(1,-24),18,bold,12,ivory)
	list.Name="Members"
	list.RichText=true
	list.TextWrapped=true
	list.TextYAlignment=Enum.TextYAlignment.Top
	list.TextTruncate=Enum.TextTruncate.None
	hudFrame.Activated:Connect(function() if Pages.openTo then Pages.openTo("Hunt","Dungeon") end end)
	-- Q / R: fire the Eclipse Heart's ability prompts (the server validates both).
	local function heartPrompt(action)
		local ok,found=pcall(function()
			local arena=workspace:FindFirstChild("The Hollow Observatory")
			local heart=arena and arena:FindFirstChild("Eclipse Heart")
			if not heart then return nil end
			for _,child in ipairs(heart:GetChildren()) do
				if child.ClassName=="ProximityPrompt" and child.ActionText==action then return child end
			end
			return nil
		end)
		return ok and found or nil
	end
	function dungeonUi.trigger(kind)
		local prompt=heartPrompt(kind=="ultimate" and "Ultimate" or "Class ability")
		if not prompt then notify("Stand by the Eclipse Heart to use your class abilities.") return false end
		local ok=pcall(function()
			prompt:InputHoldBegin()
			task.delay(num(prompt.HoldDuration,0)+.05,function() pcall(function() prompt:InputHoldEnd() end) end)
		end)
		return ok
	end
	local function abilityButton(name,kind,color)
		local b=make("TextButton",hudFrame,{Name=name,Text="",AutoButtonColor=true,BackgroundColor3=rgb("1B3542"),BorderSizePixel=0,
			Size=UDim2.fromOffset(100,26),Font=UI.heavy,TextSize=12,TextColor3=rgb(color),RichText=true,TextTruncate=Enum.TextTruncate.AtEnd,Visible=false})
		rounded(b,8,UI.brass)
		b.Activated:Connect(function() dungeonUi.trigger(kind) end)
		return b
	end
	local qButton=abilityButton("AbilityQ","ability","F9CC77")
	local rButton=abilityButton("AbilityR","ultimate","E8806A")
	dungeonUi.hud,dungeonUi.hudList,dungeonUi.qButton,dungeonUi.rButton=hudFrame,list,qButton,rButton
	function dungeonUi.refreshHud()
		local rows=DC and DC.parseParty(player:GetAttribute("DungeonParty")) or {}
		hudFrame.Visible=#rows>0
		if #rows==0 then return end
		local view=gui.AbsoluteSize
		local height=(view and view.Y>0) and view.Y or 720
		-- Short screens: a 100 px column between the Attack button and the right edge
		-- (glyph + level, three per line); tall screens: one row per delver.
		local short=height<520
		local width=short and 100 or 214
		local lanes=UI.lay()
		local top=lanes.rightTop
		local pad=short and 4 or 12
		local text={}
		for i,r in ipairs(rows) do
			local def=r.class and DC.defs[r.class]
			if short then
				local entry=def and paint(def.glyph..num(r.level,1),def.color) or paint("·"..escape(string.sub(r.name,1,2)),"A9BDC1")
				if i>1 then entry=((i-1)%3==0 and "\n" or " ")..entry end
				table.insert(text,entry)
			else
				table.insert(text,def and (paint(def.glyph.." "..escape(r.name),def.color).."  "..escape(def.name).." "..num(r.level,1)) or (escape(r.name).."  "..paint("unclassed","A9BDC1")))
			end
		end
		local rowsShown=short and math.min(2,math.ceil(#rows/3)) or #text
		local rowHeight=short and 13 or 18
		local titleHeight=short and 13 or 16
		title.Text=short and "PARTY" or "OBSERVATORY PARTY"
		title.TextSize=11
		title.Position,title.Size=UDim2.fromOffset(pad,4),UDim2.new(1,-2*pad,0,titleHeight)
		list.Text=short and table.concat(text) or table.concat(text,"\n")
		list.TextSize=short and 11 or 12
		list.Position=UDim2.fromOffset(pad,4+titleHeight)
		list.Size=UDim2.new(1,-2*pad,0,rowHeight*rowsShown)
		local mine=DC.defs[player:GetAttribute("DungeonClass") or ""]
		local y=4+titleHeight+rowHeight*rowsShown+4
		qButton.Visible,rButton.Visible=mine~=nil,mine~=nil
		if mine then
			local ready=num(player:GetAttribute("DungeonAbilityReady"),0)
			local inner=width-2*pad
			local gap=short and 4 or 6
			-- Phones: Q and R side by side as UI.TOUCH squares; tall screens: Q
			-- (with its ability name) and R on their own full-width rows.
			local bh=short and UI.TOUCH or 30
			if short then
				local qWidth=math.floor((inner-gap)/2)
				qButton.Position,qButton.Size=UDim2.fromOffset(pad,y),UDim2.fromOffset(qWidth,bh)
				rButton.Position,rButton.Size=UDim2.fromOffset(pad+qWidth+gap,y),UDim2.fromOffset(inner-qWidth-gap,bh)
			else
				qButton.Position,qButton.Size=UDim2.fromOffset(pad,y),UDim2.fromOffset(inner,bh)
				rButton.Position,rButton.Size=UDim2.fromOffset(pad,y+bh+gap),UDim2.fromOffset(inner,bh)
				y+=bh+gap
			end
			qButton.TextSize,rButton.TextSize=short and 11 or 12,short and 11 or 12
			if short then
				qButton.Text="Q "..(ready>0 and (ready.."s") or "✓")
			else
				qButton.Text="Q · "..escape(mine.ability.name)..(ready>0 and (" "..ready.."s") or " ready")
			end
			rButton.Text="R ×"..num(player:GetAttribute("DungeonUltimates"),0)
			y+=bh+(short and 4 or 6) -- phones: 95 px tall, clear of the action bar
		else
			y+=2
		end
		hudFrame.Position=UDim2.new(0,lanes.rightEdge,0,top)
		hudFrame.Size=UDim2.fromOffset(width,y)
	end
	for _,name in ipairs({"DungeonParty","DungeonAbilityReady","DungeonUltimates","DungeonClass","IsleSatchelOpen"}) do
		player:GetAttributeChangedSignal(name):Connect(function() dungeonUi.refreshHud() end)
	end
	dungeonUi.refreshHud()
end
end

------------------------------------------------------------------------------
-- Ledger: bank, market, merchant
------------------------------------------------------------------------------
do
local bankDirection="deposit"
local bankAmount="all"
local function drawBank()
	heading("01    /    BANK LEDGER")
	-- Balance plate: purse and vault as two big readouts.
	local balance=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,compactAtlas and 84 or 96),deep))
	balance.Name="Balance"
	rounded(balance,12,UI.brass)
	UI.sheen(balance,1,.74)
	UI.bevel(balance,12)
	UI.corners(balance,gold,5,6)
	local crest=motif(balance,"Ledger",compactAtlas and 40 or 48)
	crest.Position=UDim2.new(0,14,.5,compactAtlas and -20 or -24)
	local x=compactAtlas and 64 or 76
	for index,entry in ipairs({{"PURSE",num(state.coins,0),gold},{"VAULT",num(state.bank,0),mint}}) do
		local column=make("Frame",balance,{Name=entry[1],BackgroundTransparency=1,Position=UDim2.new((index-1)*.5,index==1 and x or 8,0,compactAtlas and 10 or 12),Size=UDim2.new(.5,index==1 and -x or -20,0,52)})
		label(column,entry[1],0,0,full,16,UI.heavy,11,entry[3])
		label(column,fmt(entry[2]),0,16,full,32,book,compactAtlas and 15 or 18,ivory)
	end
	local note=label(balance,"Vault coins are protected from death loss.",x,0,UDim.new(1,-x-12),18,regular,compactAtlas and 12 or 12,muted)
	note.Position=UDim2.new(0,x,1,compactAtlas and -22 or -26)
	local direction=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,UI.TOUCH),ink))
	direction.BackgroundTransparency=1
	for index,option in ipairs({{"deposit","Deposit"},{"withdraw","Withdraw"}}) do
		local selected=option[1]
		local control=button(direction,option[2],UDim2.new((index-1)*.5,index==1 and 0 or 4,0,0),UDim2.new(.5,-4,0,UI.TOUCH),function() bankDirection=selected;render() end)
		UI.tone(control,bankDirection==selected and "selected" or nil)
	end
	local entry=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,46),track))
	entry.Name="AmountField"
	rounded(entry,10,UI.line)
	label(entry,"AMOUNT",14,0,UDim.new(0,72),46,UI.heavy,11,gold)
	local input=make("TextBox",entry,{Name="BankAmount",Position=UDim2.fromOffset(90,0),Size=UDim2.new(1,-100,0,46),BackgroundTransparency=1,Text=bankAmount,PlaceholderText="Whole coins, half or all",PlaceholderColor3=muted,TextColor3=ivory,TextSize=17,Font=UI.heavy,ClearTextOnFocus=false,TextXAlignment=Enum.TextXAlignment.Left,Selectable=true,MultiLine=false})
	local presets=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,UI.TOUCH),ink))
	presets.BackgroundTransparency=1
	local preview=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,46),deep))
	rounded(preview,10,UI.line)
	local projected=label(preview,"",14,4,UDim.new(1,-28),38,regular,compactAtlas and 12 or 13,muted)
	projected.TextWrapped=true
	projected.TextTruncate=Enum.TextTruncate.None
	local transferRow=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,44),ink))
	transferRow.BackgroundTransparency=1
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
	transfer=button(transferRow,"Transfer",UDim2.fromOffset(1,0),UDim2.new(1,-2,0,44),function()
		local amount,raw,problem=requested()
		if not amount then notify(problem);return end
		send(bankDirection,raw..":"..tostring(state.bankRevision or 0))
	end)
	UI.tone(transfer,"primary")
	for index,preset in ipairs({"25","100","half","all"}) do
		button(presets,preset=="half" and "Half" or (preset=="all" and "All" or preset),UDim2.new((index-1)/4,index==1 and 1 or 2,0,0),UDim2.new(.25,-4,0,UI.TOUCH),function()
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
	local field=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,70),track))
	field.Name="Field"
	rounded(field,10,UI.line)
	label(field,title,14,6,UDim.new(1,-28),18,UI.heavy,11,gold)
	local box=make("TextBox",field,{Name=title:gsub("[^%w]","").."Input",Position=UDim2.fromOffset(14,24),Size=UDim2.new(1,-28,0,44),BackgroundTransparency=1,Text=value,PlaceholderText="1–10,000 whole coins per lot",PlaceholderColor3=muted,TextColor3=ivory,TextSize=17,Font=UI.heavy,ClearTextOnFocus=false,Selectable=true,TextXAlignment=Enum.TextXAlignment.Left,MultiLine=false})
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
	-- §36: the ruling council's Open Ledger perk (term perks from snapshot.council) cuts the fee.
	local council=Data and type(Data.Council)=="table" and Data.Council
	if council and rules and type(rules.auctionFee)=="function" then
		return council.auctionFee(council.effects(tbl(tbl(state.council).term).perks),price)
	end
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
	local field=listItem(panel(scroll,UDim2.new(),UDim2.new(1,-7,0,70),track))
	field.Name="Field"
	rounded(field,10,UI.line)
	label(field,title,14,6,UDim.new(1,-28),18,UI.heavy,11,gold)
	local box=make("TextBox",field,{Name=name,Position=UDim2.fromOffset(14,24),Size=UDim2.new(1,-28,0,44),BackgroundTransparency=1,Text=value,PlaceholderText=placeholder,PlaceholderColor3=muted,TextColor3=ivory,TextSize=17,Font=UI.heavy,ClearTextOnFocus=false,Selectable=true,TextXAlignment=Enum.TextXAlignment.Left,MultiLine=false})
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
-- Order book: asks over bids, each level a row with a depth bar sized by
-- quantity, the spread on a brass divider between them.
function U.book(view)
	return function(body,nextOrder)
		local asks,bids=tbl(view.asks),tbl(view.bids)
		local most=1
		for _,level in ipairs(asks) do most=math.max(most,num(tbl(level).qty,0)) end
		for _,level in ipairs(bids) do most=math.max(most,num(tbl(level).qty,0)) end
		local book=make("Frame",body,{Name="OrderBook",BackgroundColor3=track,BackgroundTransparency=.35,Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,LayoutOrder=nextOrder(),BorderSizePixel=0})
		make("UICorner",book,{CornerRadius=UDim.new(0,8)})
		make("UIStroke",book,{Color=UI.line,Thickness=1})
		make("UIListLayout",book,{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,2)})
		make("UIPadding",book,{PaddingTop=UDim.new(0,6),PaddingBottom=UDim.new(0,6),PaddingLeft=UDim.new(0,8),PaddingRight=UDim.new(0,8)})
		local index=0
		local function line(text,meta,hex,fraction)
			index+=1
			local h=compactAtlas and 20 or 22
			local row=make("Frame",book,{Name="Level",BackgroundTransparency=1,Size=UDim2.new(1,0,0,h),LayoutOrder=index})
			if fraction then
				local depthBar=make("Frame",row,{Name="Depth",AnchorPoint=Vector2.new(1,0),Position=UDim2.fromScale(1,0),Size=UDim2.fromScale(math.clamp(fraction,.04,1),1),BackgroundColor3=rgb(hex),BackgroundTransparency=.82,BorderSizePixel=0})
				make("UICorner",depthBar,{CornerRadius=UDim.new(0,4)})
			end
			local left=label(row,text,6,0,UDim.new(.6,-6),h,UI.heavy,compactAtlas and 12 or 13,rgb(hex))
			left.RichText=true
			if meta then
				local right=label(row,meta,0,0,UDim.new(.4,-8),h,bold,compactAtlas and 12 or 12,muted)
				right.Position=UDim2.new(.6,0,0,0)
				right.TextXAlignment=Enum.TextXAlignment.Right
			end
			return row
		end
		for i=math.min(5,#asks),1,-1 do
			local level=tbl(asks[i])
			line("ASK  "..fmt(level.price).."  ×"..fmt(level.qty),fmt(level.orders).." order"..(num(level.orders,0)==1 and "" or "s"),"EF7D67",num(level.qty,0)/most)
		end
		if #asks==0 then line("No sell offers",nil,"EF7D67") end
		local spread=line("— spread "..(view.spread and fmt(view.spread).." coins" or "—").." —",nil,"F3C66E")
		spread:FindFirstChildOfClass("TextLabel").TextXAlignment=Enum.TextXAlignment.Center
		spread:FindFirstChildOfClass("TextLabel").Size=UDim2.new(1,-12,1,0)
		UI.rule(spread,UI.brass,(compactAtlas and 20 or 22)-1,0).BackgroundTransparency=.5
		for i=1,math.min(5,#bids) do
			local level=tbl(bids[i])
			line("BID  "..fmt(level.price).."  ×"..fmt(level.qty),fmt(level.orders).." order"..(num(level.orders,0)==1 and "" or "s"),"7FE3CC",num(level.qty,0)/most)
		end
		if #bids==0 then line("No buy orders",nil,"7FE3CC") end
	end
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
	U.history=fresh and type(view.history)=="table" and view.history or nil -- §33 drawn under the book card
	card({name="Book",item=item,title=escape(itemName(item)),titleColor=rgb(itemHex(item)),
		subtitle="Held ×"..fmt(held).."  ·  merchant "..fmt(num(def and def.value,0)).." each",
		badge=fresh and view.bestBid and (fmt(view.bestBid).." bid") or nil,badgeColor=mint,
		detail=fresh and ("Best ask "..(view.bestAsk and fmt(view.bestAsk) or "—").."  ·  best bid "..(view.bestBid and fmt(view.bestBid) or "—").."  ·  spread "..(view.spread and fmt(view.spread) or "—")..". Prices are per unit; your own orders are excluded from the best prices.") or "Refresh to read this order book.",
		after=fresh and U.book(view) or nil,
		actions={{caption="Refresh",fn=function() U.refresh("Orders") end}}})
	if U.history and Pages.SYS then Pages.SYS.historyCard(item,U.history,"BookHistory") end -- §33 price history
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
-- Journal → Calendar (Events team): the Skyward Calendar, live/next events with
-- countdowns, the Starfall gift and the Festival Vendor. Dates come from the
-- shared Data.calendarAt (deterministic from server time); claims and vendor
-- access from snapshot.events. Countdown labels tick in place every second;
-- the page redraws only when a day or event boundary passes.
------------------------------------------------------------------------------
do
local CAL={timers={},boundary=math.huge,icons={BloomtideFair="Sunwheat",GlimmertideFestival="SunscaleCarp",DeepveinSurge="Brassite",HollowNight="GloamCandyOrb",StarfallVigil="StarfallShard"}}
function CAL.ready()
	return Data and type(Data.calendarAt)=="function" and type(Data.Events)=="table" and type(Data.EventVendor)=="table"
		and type(Data.upcomingEvents)=="function" and type(Data.SeasonById)=="table"
end
-- Synced server clock where available (device clocks drift), else os.time().
function CAL.now()
	local ok,t=pcall(function() return workspace:GetServerTimeNow() end)
	-- Stubbed or unsynced clocks report ~0; anything before 2020 falls back to os.time().
	return math.floor(if ok and type(t)=="number" and t==t and t>1577836800 then t else os.time())
end
function CAL.featured()
	local ok,id=pcall(function() return workspace:GetAttribute("FestivalResource") end)
	return if ok and type(id)=="string" and itemDef(id) then itemName(id) else "voting…"
end
function CAL.span(seconds)
	seconds=math.max(0,math.floor(num(seconds,0)))
	if seconds>=86400 then return (seconds//86400).."d "..((seconds%86400)//3600).."h" end
	if seconds>=3600 then return (seconds//3600).."h "..string.format("%02d",(seconds%3600)//60).."m" end
	return (seconds//60).."m "..string.format("%02d",seconds%60).."s"
end
function CAL.listText(map,have)
	local parts={}
	for id,n in pairs(tbl(map)) do
		local text=fmt(n).." "..escape(itemName(id))
		if have then text=(count("items",id)>=n and check or cross).." "..text.."  "..paint("("..fmt(count("items",id))..")","B9C7CC") end
		table.insert(parts,text)
	end
	table.sort(parts)
	return table.concat(parts,"   ")
end
-- A countdown paragraph inside a card body; fn(now) returns its text.
function CAL.timer(fn,color)
	return function(body,nextOrder)
		local copy=para(body,fn(CAL.now()),nextOrder(),color or gold,compactAtlas and 13 or 14)
		copy.Name="Countdown"
		table.insert(CAL.timers,{label=copy,fn=fn})
	end
end
function CAL.when(cal,w)
	local d=Data.calendarAt(w.starts)
	return d.seasonName.." "..d.day..(if d.year~=cal.year then "  ·  Year "..d.year else "")
end
local function drawCalendar()
	table.clear(CAL.timers)
	CAL.boundary=math.huge
	heading("SKYWARD CALENDAR    /    SEASONS & FESTIVALS")
	if not CAL.ready() then dataMissing() return end
	local now=CAL.now()
	local cal=Data.calendarAt(now)
	local season=tbl(Data.SeasonById[cal.season])
	local events=tbl(state.events)
	local claims=tbl(events.claims)
	local perSeason=num(Data.Calendar.daysPerSeason,12)
	CAL.boundary=math.min(cal.dayEnds,cal.eventEnds or math.huge)
	local labels={}
	for i,s in ipairs(Data.Calendar.seasons) do labels[i]=compactAtlas and s.name:sub(1,5) or s.name end
	card({name="CalendarToday",motif="Journal",title=paint(escape(season.name or cal.season).." "..cal.day,season.color or "F9CC77"),
		subtitle="Year "..fmt(cal.year).."  ·  day "..cal.dayOfYear.." of "..num(Data.Calendar.daysPerYear,48).."  ·  day "..cal.day.." of "..perSeason.." this season",
		badge=paint(string.upper(tostring(season.skill or "")),"9EE7D2"),detail=escape(season.text or ""),
		pips={total=#Data.Calendar.seasons,filled=cal.seasonIndex,color=safeColor(season.color,gold),labels=labels},
		bar={fraction=(now-cal.dayStart)/Data.Calendar.dayLength,color=safeColor(season.color,mint),caption="Isle day "..cal.day.." of "..perSeason},
		after=CAL.timer(function(t) return "Dusk in "..CAL.span(cal.dayEnds-t).."   ·   "..escape(season.name or "").." ends in "..CAL.span(cal.seasonEnds-t) end,muted)})
	local upcoming=Data.upcomingEvents(now,14)
	if cal.event then
		local ev=tbl(Data.Events[cal.event])
		local claimed=claims[cal.eventKey]~=nil
		local actions=nil
		if ev.gift then
			actions={{caption=claimed and "Opened" or "Claim gift",primary=not claimed,disabled=claimed,reason="You already opened this vigil's gift.",name="CalendarClaim",
				fn=function() send("eventGift") end}}
		end
		card({name="CalendarLive",item=CAL.icons[cal.event],title=paint("NOW  ·  "..escape(ev.name or cal.event),ev.color or "F9CC77"),
			subtitle=escape(season.name or "").." "..cal.day.."  ·  "..math.floor(num(ev.duration,0)/60).."-minute festival",badge=paint("LIVE","9EE7D2"),
			detail=escape(ev.text or ""),accent=safeColor(ev.color,gold),
			lines={ev.gift and ("Gift: "..CAL.listText(ev.gift)..(claimed and ("  "..paint("✓ opened","9EE7D2")) or "")) or nil,
				ev.drop and ("Festival-only: "..escape(itemName(ev.drop.item)).." ("..chance(ev.drop.chance).." per catch)") or nil,
				ev.candy and ("Event drop: "..escape(itemName(ev.candy.item)).." ("..chance(ev.candy.chance).." per kill)") or nil,
				ev.featuredMult and ("Featured crop: "..escape(CAL.featured()).."  (vote at the Island Assembly)") or nil},
			bar={fraction=(now-num(cal.eventStarts,now))/math.max(1,num(ev.duration,1)),color=safeColor(ev.color,mint),caption="Festival underway"},
			after=CAL.timer(function(t) return "Ends in "..CAL.span(cal.eventEnds-t) end),actions=actions})
	end
	heading("UPCOMING FESTIVALS")
	local shown,listed=0,{[cal.event or ""]=true} -- next occurrence of each other festival
	for _,w in ipairs(upcoming) do
		if not listed[w.id] and shown<(compactAtlas and 3 or 4) then
			listed[w.id]=true
			shown+=1
			local ev=tbl(Data.Events[w.id])
			CAL.boundary=math.min(CAL.boundary,w.starts)
			card({name="CalendarNext"..shown,item=CAL.icons[w.id],title=paint(escape(ev.name or w.id),ev.color or "FFF4D9"),
				subtitle=escape(CAL.when(cal,w)).."  ·  "..math.floor(num(ev.duration,0)/60).." minutes",detail=escape(ev.text or ""),
				after=CAL.timer(function(t) return "Starts in "..CAL.span(w.starts-t) end,mint)})
		end
	end
	local open=num(events.vendorUntil,0)>now
	heading("FESTIVAL VENDOR    /    "..(open and "OPEN" or "VISIT THE HUB STALL"))
	if not open then
		card({name="VendorClosed",motif="Ledger",title="Festival Vendor",titleColor=gold,subtitle="Compass Quay stall beside the Island Assembly board",
			detail="Trade Hollow Night candy, Starfall shards and Sunscale Carp for keepsakes. Visit the stall to open trading for "..math.floor(num(Data.EVENT_VENDOR_SECONDS,300)/60).." minutes."})
	else
		card({name="VendorOpen",motif="Ledger",title="Festival Vendor",titleColor=gold,subtitle="Trading open",
			after=CAL.timer(function(t) return "Stall closes in "..CAL.span(num(events.vendorUntil,0)-t) end,muted)})
	end
	for _,offer in ipairs(Data.EventVendor) do
		local rewardId=next(tbl(offer.reward))
		local def=itemDef(rewardId)
		local afford=true
		for id,n in pairs(tbl(offer.costs)) do if count("items",id)<n then afford=false end end
		local owned=offer.unique==true and count("items",rewardId)>0
		local reason=(not open and "Visit the Festival Vendor on the hub first.") or (owned and "You already own one.") or (not afford and "You need more event currency.") or nil
		card({name="Offer"..offer.id,item=rewardId,title=escape(CAL.listText(offer.reward)),titleColor=def and safeColor(rarityHex(def.rarity),ivory) or ivory,
			subtitle=def and escape(def.rarity or "").."  ·  "..escape(def.kind or "") or nil,badge=owned and paint("OWNED","9EE7D2") or nil,
			detail=def and escape(def.description or "") or nil,lines={"Cost: "..CAL.listText(offer.costs,true)},
			actions={{caption="Trade",primary=reason==nil,disabled=reason~=nil,reason=reason,name="Trade"..offer.id,fn=function() send("eventTrade",offer.id) end}}})
	end
end
Pages.drawCalendar=drawCalendar
task.spawn(function()
	while task.wait(1) do
		if #CAL.timers>0 and atlas.Visible and current=="Journal" and sectionOf and sectionOf.Journal=="Calendar" then
			local now=CAL.now()
			if now>=CAL.boundary then render() else
				for _,t in ipairs(CAL.timers) do pcall(function() t.label.Text=t.fn(now) end) end
			end
		end
	end
end)
end

------------------------------------------------------------------------------
-- Journal › Council (Isle Council team, §36): the ruling term (winner,
-- minister, active perks, countdown), the open ballot (five candidates, their
-- perks, the cached live vote share, Vote / change buttons) and past terms.
-- Slates and perk text come from Data.Council (deterministic per election);
-- votes, tallies and results from snapshot.council. Countdowns tick in place;
-- the page redraws when the ballot opens or closes.
------------------------------------------------------------------------------
do
local CO={timers={},boundary=math.huge,readySnap=nil,readyAt=0}
function CO.ready() return Data and type(Data.Council)=="table" and type(Data.Council.slate)=="function" end
-- Synced server clock; unsynced clocks fall back to the snapshot's server time, then os.time().
function CO.now()
	local ok,t=pcall(function() return workspace:GetServerTimeNow() end)
	if ok and type(t)=="number" and t==t and t>1577836800 then return math.floor(t) end
	local snap=num(tbl(state.council).now,0)
	return math.floor(if snap>1577836800 then snap else os.time())
end
function CO.timer(fn,color)
	return function(body,nextOrder)
		local copy=para(body,fn(CO.now()),nextOrder(),color or gold,compactAtlas and 13 or 14)
		copy.Name="Countdown"
		table.insert(CO.timers,{label=copy,fn=fn})
	end
end
-- A portrait medallion in the candidate's colour.
function CO.portrait(cand)
	return function(band,size)
		local disc=make("TextLabel",band,{Name="Portrait",Size=UDim2.fromOffset(size,size),BackgroundColor3=safeColor(cand.color,gold),BackgroundTransparency=.55,
			Text=cand.portrait or "?",TextSize=math.floor(size*.55),Font=Enum.Font.GothamBold,TextColor3=ivory,BorderSizePixel=0})
		make("UICorner",disc,{CornerRadius=UDim.new(1,0)})
		make("UIStroke",disc,{Color=safeColor(cand.color,gold),Thickness=2})
		return disc
	end
end
function CO.perkLines(ids,minister)
	local C=Data.Council
	local out={}
	for _,id in ipairs(tbl(ids)) do
		local p=C.Perks[id]
		if p then table.insert(out,paint("◆ "..escape(p.name),p.color).."  "..escape(p.text)..(if id==minister then "  "..paint("(Minister)","B9C7CC") else "")) end
	end
	return out
end
local function drawCouncil()
	table.clear(CO.timers)
	CO.boundary=math.huge
	heading("ISLE COUNCIL    /    ELECTION & TERM")
	if not CO.ready() then dataMissing() return end
	local C=Data.Council
	local s=tbl(state.council)
	local now=CO.now()
	-- QC L4: the server's election (it rolls forward; a lagging client clock never
	-- shows an older ballot) while its window still holds, else the client's clock.
	local el=C.election(now)
	local se=math.floor(num(s.e,0))
	if se>0 then
		local w=C.termWindow(se)
		if now<w.starts then
			el={e=se,opens=w.opens,closes=w.starts,open=s.open==true and now>=w.opens,termYear=se-1}
		end
	end
	local boundary=if el.open then el.closes else el.opens
	CO.boundary=if boundary>now then boundary else math.huge
	-- QC L2: the vote cooldown is a deadline: the page redraws when it passes.
	if s~=CO.readySnap then CO.readySnap=s; CO.readyAt=now+math.max(0,num(s.readyIn,0)) end
	local wait=math.max(0,CO.readyAt-now)
	if wait>0 then CO.boundary=math.min(CO.boundary,CO.readyAt) end
	local term=tbl(s.term)
	-- The ruling term.
	if term.sealed and type(term.winner)=="string" then
		local w=C.CandidateById[term.winner] or {}
		local lines=CO.perkLines(term.perks,term.ministerPerk)
		if type(term.minister)=="string" then table.insert(lines,1,"Minister: "..paint(escape(C.candidateName(term.minister)),"FFF4D9")..(if term.ministerPerk then "" else "  (no extra perk)")) end
		local total=num(term.total,0)
		card({name="CouncilTerm",icon=CO.portrait(w),accent=safeColor(w.color,gold),title=paint("YEAR "..num(term.y,0).." COUNCIL  ·  "..escape(w.name or term.winner),C.COLOR),
			subtitle=escape(w.title or "").."  ·  "..fmt(total).." vote"..(if total==1 then "" else "s").." cast",badge=paint("IN OFFICE","9EE7D2"),
			detail="Active on every isle this year:",lines=lines,
			after=CO.timer(function(t) return "Term ends in "..C.span(num(term.ends,t)-t) end,muted)})
	else
		card({name="CouncilTerm",motif="Journal",title=paint("YEAR "..num(term.y,el.termYear).." COUNCIL",C.COLOR),subtitle="Counting the ballot…",
			detail="The isles are sealing last year's ballot. Council perks begin as soon as the result is in."})
	end
	-- The ballot.
	local voted=type(s.vote)=="string" and s.vote or nil
	-- QC L1: a refused ballot and the candidate last confirmed by the count.
	local REFUSED={closed="not counted: the ballot had closed",late="not counted: the ballot closed before it was written",
		full="not counted: the ballot box is full",bad="not counted: refused"}
	local status=if s.refused then paint("✗ "..(REFUSED[s.refused] or REFUSED.bad),"E07A5F") elseif s.confirmed then paint("✓ counted","9EE7D2") else paint("counting…","B9C7CC")
	local yourVote=if voted then "Your vote: "..paint(escape(C.candidateName(voted)),"FFF4D9").."  "..status else "You have not voted yet."
	local ballotLines={yourVote}
	if voted and not s.confirmed and type(s.counted)=="string" and s.counted~=voted then
		table.insert(ballotLines,"Last counted: "..paint(escape(C.candidateName(s.counted)),"FFF4D9"))
	end
	local minRenown=math.floor(num(s.minRenown,C.MIN_RENOWN or 0))
	local ineligible=s.eligible==false
	if ineligible then table.insert(ballotLines,paint("Voting needs Isle Renown "..minRenown.." (you are Renown "..math.floor(num(s.renown,0))..")","E9C46A")) end
	if el.open then
		card({name="CouncilBallot",motif="Ledger",accent=gold,title=paint("YEAR "..el.e.." BALLOT  ·  OPEN",C.COLOR),
			subtitle="One vote per account  ·  change it any time before the close",badge=paint("VOTING","9EE7D2"),
			lines=(function() table.insert(ballotLines,"Changes left: "..math.max(0,num(s.changesLeft,C.MAX_CHANGES)-(if voted then 0 else 1))) return ballotLines end)(),
			after=CO.timer(function(t) return "Ballot closes in "..C.span(el.closes-t) end)})
	else
		card({name="CouncilBallot",motif="Ledger",title=paint("YEAR "..el.e.." BALLOT",C.COLOR),subtitle="Opens on Emberfall 1",
			detail="Five councillors stand each isle year. Read their perks now; voting opens with the season.",
			after=CO.timer(function(t) return "Ballot opens in "..C.span(el.opens-t) end,mint)})
	end
	heading("CANDIDATES    /    YEAR "..el.e)
	local counts=type(s.counts)=="table" and s.counts or nil
	local total=num(s.total,0)
	local shares=counts and C.shares(counts,total) or nil
	for i,entry in ipairs(C.slate(el.e)) do
		local cand=C.CandidateById[entry.id]
		local mine=voted==entry.id
		local reason=(not el.open and "The ballot is not open yet.") or (ineligible and "Voting needs Isle Renown "..minRenown..".") or (mine and "Your vote is already with "..cand.name..".")
			or (num(s.changesLeft,C.MAX_CHANGES)<=0 and "You have no vote changes left this election.") or (wait>0 and "One moment: the clerk is inking your last ballot.") or nil
		local bar=nil
		if shares then
			local votes=math.floor(num(counts[i],0))
			bar={fraction=shares[i],color=safeColor(cand.color,gold),caption=string.format("%.1f%%",shares[i]*100).."  ·  "..fmt(votes).." vote"..(if votes==1 then "" else "s")}
		end
		card({name="CouncilCandidate"..entry.id,icon=CO.portrait(cand),accent=mine and gold or nil,edge=mine and gold or nil,
			title=paint(escape(cand.name),cand.color),subtitle=escape(cand.title),badge=mine and paint("YOUR VOTE","9EE7D2") or nil,
			detail="“"..escape(cand.pitch).."”",lines=CO.perkLines(entry.perks),bar=bar,
			actions={{caption=if mine then "Voted" elseif voted then "Change vote" else "Vote",primary=reason==nil,disabled=reason~=nil,reason=reason,
				name="CouncilVote"..entry.id,fn=function() send("councilVote",entry.id) end}}})
	end
	if el.open then
		local age=if s.tallyAt then math.max(0,now-num(s.tallyAt,now)) else nil
		card({name="CouncilTally",motif="Ledger",title="Live vote share",titleColor=gold,
			detail=if shares then fmt(total).." votes counted across every isle  ·  updated "..(if age and age>=60 then (age//60).."m" else "moments").." ago (refreshes about every "..math.floor(C.READ/60*10+.5)/10 .."m)"
				else "The tally is being gathered from every isle…",
			actions={{caption="Refresh",name="CouncilRefresh",fn=function() send("councilView") end}}})
	end
	heading("PAST COUNCILS")
	local hist=tbl(s.history)
	if #hist==0 then card({name="CouncilHistoryEmpty",motif="Journal",title="No sealed terms yet",titleColor=muted,detail="Past winners appear here once a ballot is sealed."}) end
	for _,h in ipairs(hist) do
		local w=C.CandidateById[h.winner] or {}
		-- Lead decision (b): a term nobody voted in seats its first slate place, with full perks.
		local share=if num(h.total,0)>0 then string.format("%.0f%%",num(h.votes,0)/h.total*100).." of "..fmt(num(h.total,0)).." votes" else "No votes cast: first on the slate"
		card({name="CouncilHistory"..tostring(h.e),icon=CO.portrait(w),title=paint("Year "..num(h.e,0).."  ·  "..escape(w.name or tostring(h.winner)),w.color or C.COLOR),
			subtitle=share..(if type(h.minister)=="string" then "  ·  Minister "..escape(C.candidateName(h.minister)) else ""),
			lines=CO.perkLines(C.termPerks({e=h.e,winner=h.winner,ministerPerk=h.ministerPerk}),h.ministerPerk)})
	end
end
Pages.drawCouncil=drawCouncil
Pages.CO=CO
task.spawn(function()
	while task.wait(1) do
		if #CO.timers>0 and atlas.Visible and current=="Journal" and sectionOf and sectionOf.Journal=="Council" then
			local now=CO.now()
			if now>=CO.boundary then render() else
				for _,t in ipairs(CO.timers) do pcall(function() t.label.Text=t.fn(now) end) end
			end
		end
	end
end)
end

------------------------------------------------------------------------------
-- Agility & Hunter (Agility/Hunter client team). HUD: a lap tracker (course,
-- obstacle n/total, step countdown, lap clock and best lap, an arrow to the
-- next obstacle) and a trap counter (placed/max, caught, collapsed) at the
-- top of the left column. Pages: Journal › Agility (courses,
-- lap milestones, shortcuts), Hunt › Hunter (hunter log, traps, companions)
-- and Ledger › Vendors (Skymark Exchange, Trackers' Lodge; verb skillBuy).
-- Server state: snapshot.agilityHunter = {agility={laps,best,lapTiers,run},
-- hunter={log,logTiers,traps,maxTraps}, vendor={skill,openUntil}}; player
-- attributes AgilityRun ("<course>:<next>:<total>"), AgilityRunExpires,
-- HunterTraps ("n/max"), HunterTrapsCaught, SkillVendor(+Until). Wayfinder
-- (nav.client.lua) adds AgilityNextAt (next obstacle position, local) and
-- HunterTrapsCollapsed (own collapsed traps, local).
------------------------------------------------------------------------------
do
local AH={timers={},vendor="Agility",hex={Agility="62C2B0",Hunter="A8763E"}}
Pages.AH=AH
function AH.ready() return Data and type(Data.Agility)=="table" and type(Data.Hunter)=="table" and type(Data.SkillVendors)=="table" end
function AH.now()
	local ok,t=pcall(function() return workspace:GetServerTimeNow() end)
	return math.floor(if ok and type(t)=="number" and t==t and t>1577836800 then t else os.time())
end
function AH.state() return tbl(state.agilityHunter) end
function AH.level(skill) local info=skillsOf(state)[skill] return info and info.level or 1 end
-- 41.2 → "41.2s", 75.3 → "1:15.3".
function AH.lapTime(seconds)
	seconds=num(seconds,nil)
	if not seconds then return "—" end
	local tenths=math.floor(seconds*10+.5)
	if tenths>=600 then return string.format("%d:%04.1f",tenths//600,(tenths%600)/10) end
	return string.format("%.1fs",tenths/10)
end
function AH.mmss(seconds)
	seconds=math.max(0,math.floor(num(seconds,0)))
	return string.format("%d:%02d",seconds//60,seconds%60)
end
function AH.guide(specs,label)
	local request=player:FindFirstChild("WayfinderRequest")
	if request then
		request:Fire(specs,label)
		if atlas.Visible then closeAtlas() end
	else
		notify("The Wayfinder is still charting the isles. Try again in a moment.")
	end
end
-- Run attribute → course def, next index, total ("" or malformed → nil).
function AH.run()
	if not AH.ready() then return nil end
	local value=player:GetAttribute("AgilityRun")
	local id,nextIndex,total
	if type(value)=="string" then id,nextIndex,total=value:match("^(%w+):(%d+):(%d+)$") end
	local course=id and Data.Agility.CourseById[id]
	if not course then return nil end
	return course,tonumber(nextIndex),tonumber(total)
end

------------------------------------------------------------------------------
-- HUD
------------------------------------------------------------------------------
do
	local tracker=make("TextButton",gui,{Name="CourseTracker",Text="",AutoButtonColor=false,BackgroundColor3=deep,BackgroundTransparency=.06,BorderSizePixel=0,
		Position=UDim2.fromOffset(10,174),Size=UDim2.fromOffset(250,70),Visible=false,Selectable=false})
	rounded(tracker,12,UI.brass)
	UI.sheen(tracker,1,.74)
	local accent=make("Frame",tracker,{Name="Accent",Position=UDim2.fromOffset(0,10),Size=UDim2.new(0,3,1,-20),BackgroundColor3=rgb(AH.hex.Agility),BorderSizePixel=0})
	make("UICorner",accent,{CornerRadius=UDim.new(1,0)})
	AH.courseName=label(tracker,"",12,4,UDim.new(1,-74),16,UI.heavy,11,rgb(lighten(AH.hex.Agility,.3)))
	AH.courseName.Name="Course"
	AH.courseStep=label(tracker,"",0,4,UDim.new(0,58),16,UI.heavy,12,ivory)
	AH.courseStep.Name="Step"
	AH.courseStep.Position=UDim2.new(1,-66,0,4)
	AH.courseStep.TextXAlignment=Enum.TextXAlignment.Right
	AH.arrow=make("TextLabel",tracker,{Name="Arrow",Position=UDim2.fromOffset(11,21),Size=UDim2.fromOffset(18,18),BackgroundColor3=rgb("1B3542"),
		Text="▲",Font=UI.heavy,TextSize=11,TextColor3=gold,BorderSizePixel=0})
	make("UICorner",AH.arrow,{CornerRadius=UDim.new(1,0)})
	make("UIStroke",AH.arrow,{Color=UI.brass,Thickness=1,Transparency=.3})
	AH.nextName=label(tracker,"",34,20,UDim.new(1,-100),20,bold,13,ivory)
	AH.nextName.Name="Next"
	AH.nextName.RichText=true
	AH.countdown=label(tracker,"",0,20,UDim.new(0,60),20,UI.heavy,14,gold)
	AH.countdown.Name="Countdown"
	AH.countdown.Position=UDim2.new(1,-68,0,20)
	AH.countdown.TextXAlignment=Enum.TextXAlignment.Right
	AH.steps=make("Frame",tracker,{Name="Steps",Position=UDim2.fromOffset(12,44),Size=UDim2.new(1,-24,0,5),BackgroundTransparency=1})
	AH.lapLine=label(tracker,"",12,51,UDim.new(1,-24),15,bold,11,muted)
	AH.lapLine.Name="Lap"
	AH.lapLine.RichText=true
	tracker.Activated:Connect(function() if Pages.openTo then Pages.openTo("Journal","Agility") end end)
	AH.tracker=tracker

	local traps=make("TextButton",gui,{Name="TrapTracker",Text="",AutoButtonColor=false,BackgroundColor3=deep,BackgroundTransparency=.06,BorderSizePixel=0,
		Position=UDim2.fromOffset(10,250),Size=UDim2.fromOffset(250,30),Visible=false,Selectable=false})
	rounded(traps,12,UI.brass)
	UI.sheen(traps,1,.74)
	UI.chip(traps,"◉",rgb(AH.hex.Hunter),22,5)
	AH.trapText=label(traps,"",33,0,UDim.new(1,-120),30,UI.heavy,13,ivory)
	AH.trapText.Name="Count"
	AH.trapState=label(traps,"",0,0,UDim.new(0,100),30,UI.heavy,12,mint)
	AH.trapState.Name="State"
	AH.trapState.RichText=true
	AH.trapState.Position=UDim2.new(1,-108,0,0)
	AH.trapState.TextXAlignment=Enum.TextXAlignment.Right
	traps.Activated:Connect(function() if Pages.openTo then Pages.openTo("Hunt","Hunter") end end)
	AH.traps=traps
end
-- Top of the left column (lanes.leftTop; the old tutorial tracker that sat
-- above it is retired, Polish); 184 px wide on short screens so it clears the
-- centred toast. When both panels would reach the action bar (phone
-- landscape) the lap tracker drops its best-lap line and the trap counter
-- slims down.
-- The island builder and townsfolk dialogue own the bottom and left: step aside.
function AH.suppressed()
	if player:GetAttribute("IslandBuilding") then return true end
	local playerGui=player:FindFirstChild("PlayerGui")
	local folk=playerGui and playerGui:FindFirstChild("TownsfolkDialogue")
	local box=folk and folk:FindFirstChild("Dialogue")
	return box~=nil and box.Visible==true
end
function AH.layout()
	local view=gui.AbsoluteSize
	local height=720
	if view and view.Y>0 then height=view.Y end
	local short=height<520
	local lanes=UI.lay()
	local top=lanes.leftTop
	local width=lanes.leftWidth
	local trackerHeight=short and 64 or 70
	-- The left column ends above the hotbar (x 142+ on the smallest phones).
	local floor=lanes.hotbar.y-4
	local tight=AH.tracker.Visible and AH.traps.Visible and top+trackerHeight+6+30>floor
	if tight then trackerHeight=44 end
	AH.tracker.Size=UDim2.fromOffset(width,trackerHeight)
	AH.tracker.Position=UDim2.fromOffset(10,top)
	AH.lapLine.Visible=not tight
	AH.lapLine.Position=UDim2.fromOffset(12,short and 47 or 51)
	AH.steps.Position=UDim2.fromOffset(12,tight and 37 or (short and 42 or 44))
	local trapHeight=tight and 22 or 30
	AH.traps.Position=UDim2.fromOffset(10,AH.tracker.Visible and top+trackerHeight+(tight and 4 or 6) or top)
	AH.traps.Size=UDim2.fromOffset(width,trapHeight)
	AH.trapText.Size=UDim2.new(1,width<200 and -40 or -120,0,trapHeight)
	AH.trapState.Size=UDim2.new(0,100,0,trapHeight)
	AH.trapState.Visible=width>=200
	AH.paintTraps()
end
-- Course tracker text and pips from the attributes + the latest snapshot.
AH.lap={}
function AH.refreshCourse()
	local course,nextIndex,total=AH.run()
	local was=AH.lap
	if course and nextIndex and total then
		if was.course~=course.id or (was.next or 0)>nextIndex then
			AH.lap={course=course.id,started=os.clock(),next=nextIndex}
		end
		AH.lap.next=nextIndex
		AH.lap.total=total
		AH.lap.done=nil
	elseif was.course and was.next==was.total and not was.done then
		-- The final obstacle landed: the server clears the run. Show the lap for a moment.
		local move=player:GetAttribute("AgilityMove")
		if not (type(move)=="string" and move:match("^fall")) then
			was.done=os.clock()
			was.time=os.clock()-num(was.started,os.clock())
		else
			AH.lap={}
		end
	elseif not was.done then
		AH.lap={}
	end
	local lap=AH.lap
	local def=lap.course and AH.ready() and Data.Agility.CourseById[lap.course]
	local expires=num(player:GetAttribute("AgilityRunExpires"),0)
	local stale=lap.done==nil and expires>0 and AH.now()-expires>4
	AH.tracker.Visible=def~=nil and not stale and not AH.suppressed() and (lap.done==nil or os.clock()-lap.done<4)
	AH.layout()
	if not AH.tracker.Visible then return end
	local hex=type(def.color)=="string" and def.color or AH.hex.Agility
	AH.tracker:FindFirstChild("Accent").BackgroundColor3=rgb(hex)
	AH.courseName.Text=string.upper(def.name)
	AH.courseName.TextColor3=rgb(lighten(hex,.35))
	local best=num(tbl(tbl(AH.state().agility).best)[def.id],nil)
	local totalSteps=#def.obstacles
	if lap.done then
		AH.courseStep.Text=totalSteps.." / "..totalSteps
		AH.nextName.Text=paint("LAP COMPLETE","7FE3CC")
		AH.countdown.Text=AH.lapTime(lap.time)
		AH.countdown.TextColor3=mint
		AH.arrow.Text="✓"
		AH.arrow.Rotation=0
	else
		local obstacle=def.obstacles[lap.next] or def.obstacles[1]
		local kind=Data.Agility.Kinds[obstacle.kind]
		AH.courseStep.Text=lap.next.." / "..totalSteps
		-- Narrow (phones): the obstacle name alone; the verb shows on wider screens.
		local verb=AH.tracker.Size.X.Offset>=220 and (paint(escape(kind and kind.verb or "Next"),"A9BDC1").." ") or ""
		AH.nextName.Text=verb..escape(obstacle.name)
		AH.arrow.Text="▲"
	end
	local laps=num(tbl(tbl(AH.state().agility).laps)[def.id],0)
	AH.lapLine.Text="Best "..paint(best and AH.lapTime(best) or "—","F3C66E").."   ·   "..fmt(laps).." laps"
	-- Obstacle pips: landed (course colour), next (gold), still ahead (track).
	if AH.steps:GetAttribute("Count")~=totalSteps then
		for _,child in ipairs(AH.steps:GetChildren()) do child:Destroy() end
		for i=1,totalSteps do
			local pip=make("Frame",AH.steps,{Name="Step"..i,Position=UDim2.new((i-1)/totalSteps,1,0,0),Size=UDim2.new(1/totalSteps,-3,1,0),BackgroundColor3=track,BorderSizePixel=0})
			make("UICorner",pip,{CornerRadius=UDim.new(1,0)})
		end
		AH.steps:SetAttribute("Count",totalSteps)
	end
	for i=1,totalSteps do
		local pip=AH.steps:FindFirstChild("Step"..i)
		if pip then pip.BackgroundColor3=(lap.done or i<lap.next) and rgb(hex) or (i==lap.next and gold or track) end
	end
	AH.layout()
	AH.tick()
end
-- Trap counter from HunterTraps / HunterTrapsCaught / HunterTrapsCollapsed.
function AH.refreshTraps()
	local value=player:GetAttribute("HunterTraps")
	local placed,max
	if type(value)=="string" then placed,max=value:match("^(%d+)/(%d+)$") end
	placed,max=tonumber(placed),tonumber(max)
	local caught=math.max(0,num(player:GetAttribute("HunterTrapsCaught"),0))
	local collapsed=math.max(0,num(player:GetAttribute("HunterTrapsCollapsed"),0))
	AH.traps.Visible=placed~=nil and (placed>0 or caught>0 or collapsed>0) and not AH.suppressed()
	AH.trapInfo={placed=placed or 0,max=max,caught=caught,collapsed=collapsed}
	AH.layout()
end
-- Counter copy for the current width (beside the lap tracker it is a slim chip).
function AH.paintTraps()
	local info=AH.trapInfo
	if not info then return end
	local wide=AH.trapState.Visible
	local parts={}
	if info.caught>0 then table.insert(parts,paint("✦ "..info.caught..(wide and " caught" or ""),"7FE3CC")) end
	if info.collapsed>0 then table.insert(parts,paint("✕ "..info.collapsed..((wide and info.caught==0) and " collapsed" or ""),"EF7D67")) end
	AH.trapText.RichText=true
	AH.trapText.Text=(wide and "Traps " or "")..info.placed.." / "..(info.max or "?")..(wide and "" or ("  "..table.concat(parts," ")))
	AH.trapState.Text=table.concat(parts,"  ")
end
-- Every 0.1 s while a lap runs: countdown, lap clock and the arrow's bearing
-- to AgilityNextAt relative to the camera (up = straight ahead).
function AH.tick()
	if not AH.tracker.Visible then return end
	local lap=AH.lap
	if lap.done then
		if os.clock()-lap.done>=4 then AH.lap={} AH.refreshCourse() end
		return
	end
	local expires=num(player:GetAttribute("AgilityRunExpires"),0)
	local left=expires-AH.now()
	if expires<=0 then
		AH.countdown.Text=""
	elseif left<0 then
		-- The step window passed: the server breaks the lap on the next attempt.
		AH.countdown.Text="Too slow"
		AH.countdown.TextColor3=ember
		if left<-4 then
			AH.tracker.Visible=false
			AH.layout()
		end
	else
		AH.countdown.Text=AH.mmss(left)
		AH.countdown.TextColor3=left<=8 and ember or gold
	end
	local at=player:GetAttribute("AgilityNextAt")
	local character=player.Character
	local root=character and character:FindFirstChild("HumanoidRootPart")
	if typeof(at)=="Vector3" and root then
		local camera=workspace.CurrentCamera
		local look=camera and camera.CFrame.LookVector or root.CFrame.LookVector
		local to=at-root.Position
		local angle=math.deg(math.atan2(look.X*to.Z-look.Z*to.X,look.X*to.X+look.Z*to.Z))
		AH.arrow.Rotation=math.floor(angle+.5)
		AH.arrow.TextTransparency=0
	else
		AH.arrow.TextTransparency=.6
	end
end
for _,name in ipairs({"AgilityRun","AgilityRunExpires"}) do
	player:GetAttributeChangedSignal(name):Connect(function() AH.refreshCourse() end)
end
player:GetAttributeChangedSignal("IslandBuilding"):Connect(function() AH.refreshCourse() AH.refreshTraps() end)
for _,name in ipairs({"HunterTraps","HunterTrapsCaught","HunterTrapsCollapsed"}) do
	player:GetAttributeChangedSignal(name):Connect(function() AH.refreshTraps() end)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() AH.layout() end)
function AH.onSnapshot()
	AH.refreshCourse()
	AH.refreshTraps()
end
task.spawn(function()
	while task.wait(.1) do
		if AH.tracker.Visible then pcall(AH.tick) end
	end
end)
task.spawn(function()
	-- Vendor countdowns on the open Vendors page; layout re-checks the left column.
	while task.wait(1) do
		pcall(AH.refreshCourse)
		pcall(AH.refreshTraps)
		if #AH.timers>0 and atlas.Visible and current=="Ledger" and sectionOf and sectionOf.Ledger=="Vendors" then
			local now=AH.now()
			for _,t in ipairs(AH.timers) do pcall(function() t.label.Text=t.fn(now) end) end
			if AH.closesAt and now>=AH.closesAt then render() end
		end
	end
end)

------------------------------------------------------------------------------
-- Journal › Agility
------------------------------------------------------------------------------
-- Milestone pips + bar towards the next of `tiers` for `n` completions.
function AH.milestones(n,tiers)
	local reached=0
	for i,need in ipairs(tiers) do if n>=need then reached=i end end
	local nextNeed=tiers[reached+1]
	local previous=tiers[reached] or 0
	local labels={}
	for i,need in ipairs(tiers) do labels[i]=short(need) end
	return reached,nextNeed,previous,labels
end
function AH.locked(region)
	return type(region)=="string" and player:GetAttribute(region.."Unlocked")==false
end
function AH.drawAgility()
	if not AH.ready() then dataMissing() return end
	local AG=Data.Agility
	local ag=tbl(AH.state().agility)
	local laps,best=tbl(ag.laps),tbl(ag.best)
	local level=AH.level("Agility")
	local stats=tbl(dget("stats"))
	local surefoot=num(stats.surefoot,0)
	local total,tiers=0,0
	for _,course in ipairs(AG.Courses) do
		local n=num(laps[course.id],0)
		total+=n
		for _,need in ipairs(AG.LapTiers) do if n>=need then tiers+=1 end end
	end
	tiers=num(ag.lapTiers,tiers)
	local hex=skillHex("Agility")
	local marks=count("items",AG.MARK_ITEM)
	card({name="AgilitySummary",icon=function(parent,size) return titleArt(parent,"Agility",size,"Hero") end,accent=rgb(hex),
		title="Skyrunner's log",titleColor=gold,subtitle="Agility "..level.."   ·   "..fmt(total).." laps   ·   "..fmt(marks).." Skymarks",
		badge="Lv "..level,badgeColor=rgb(lighten(hex,.3)),
		detail="Run each course's obstacles in order: start at the first, then reach the next within "..AG.STEP_WINDOW.."s of landing. Every lap pays bonus XP and may leave a Skymark for the Skymark Exchange.",
		lines={"Lap milestones ("..table.concat(AG.LapTiers," / ").." laps of any course): "..statText(AG.LapBonus).." each, permanently."..
			(tiers>0 and ("  Earned: "..statText(AG.LapBonus,tiers).." from "..tiers.." milestone"..(tiers==1 and "" or "s")..".") or ""),
			paint("❦ Surefoot "..fmt(surefoot).."%","62C2B0").." cuts every slip chance. Slips fade away "..AG.FAIL_FADE.." levels above a course."}})
	local course,nextIndex,runTotal=AH.run()
	if course and nextIndex then
		local obstacle=course.obstacles[nextIndex]
		card({name="AgilityRun",motif="Journal",accent=gold,title=paint("LAP UNDERWAY  ·  "..escape(course.name),"F3C66E"),
			subtitle="Next: "..escape(obstacle and obstacle.name or "?").."  ·  "..nextIndex.." of "..num(runTotal,#course.obstacles),
			pips={total=#course.obstacles,filled=nextIndex-1,color=safeColor(course.color,mint)},
			actions={{caption="Guide",primary=true,name="GuideNextObstacle",fn=function() AH.guide({"anchor:AgilityNext","anchor:Waypoint_Agility_"..course.id},"Next obstacle") end}}})
	end
	heading("COURSES    /    "..#AG.Courses.." SKY CIRCUITS")
	for _,c in ipairs(AG.Courses) do
		local open=level>=c.level
		local n=num(laps[c.id],0)
		local b=num(best[c.id],nil)
		local reached,nextNeed,previous,labels=AH.milestones(n,AG.LapTiers)
		local risk=0
		for _,o in ipairs(c.obstacles) do risk=math.max(risk,AG.failChance(c,o,level,surefoot)) end
		local chain={}
		for _,o in ipairs(c.obstacles) do
			local verb=tbl(AG.Kinds[o.kind]).verb or o.kind
			table.insert(chain,(num(o.risk,0)>0 and paint(escape(verb.." "..o.name),"F2A08E") or escape(verb.." "..o.name)))
		end
		local regionLocked=AH.locked(c.region)
		local lines={
			table.concat(chain,paint("  ›  ","6E8790")),
			"Lap: "..paint("+"..fmt(AG.lapTotal(c)).." XP","F3C66E").."   ·   Skymark "..chance(AG.markChance(c,level)).."   ·   Best "..paint(b and AH.lapTime(b) or "—","F7EFDC"),
			open and (risk>0 and paint("Slip chance up to "..chance(risk).." at your level","EF7D67") or paint("No slips at your level","7FE3CC")) or nil,
			regionLocked and paint("Unlock "..escape(AH.regionName(c.region)).." to reach this course.","EF7D67") or nil,
		}
		card({name="Course"..c.id,icon=function(parent,size) return itemGlyph(parent,{name=c.name,color=c.color},size,not open) end,iconSize=compactAtlas and 36 or 44,
			title=escape(c.name),titleColor=open and rgb(lighten(c.color,.35)) or muted,
			subtitle="Agility "..c.level.."   ·   "..escape(AH.regionName(c.region)).."   ·   "..#c.obstacles.." obstacles",
			badge=open and (fmt(n).." laps") or ("Lv "..c.level),badgeColor=open and ivory or ember,
			pips={total=#AG.LapTiers,filled=reached,color=safeColor(c.color,mint),labels=labels},
			bar=open and {fraction=nextNeed and math.clamp((n-previous)/math.max(1,nextNeed-previous),0,1) or 1,color=gold,
				caption=nextNeed and (fmt(n).." / "..fmt(nextNeed).." laps to milestone "..numeral(reached+1)) or "EVERY MILESTONE REACHED"} or nil,
			lines=lines,
			actions={{caption="Guide",name="Guide"..c.id,fn=function() AH.guide({"anchor:Waypoint_Agility_"..c.id,"region:"..c.region},c.name) end}}})
	end
	heading("SHORTCUTS    /    AGILITY ROUTES")
	for _,sc in ipairs(AG.Shortcuts) do
		local open=level>=sc.level
		local regionLocked=AH.locked(sc.region)
		local kind=tbl(AG.Kinds[sc.kind])
		card({name="Shortcut"..sc.id,motif="Journal",title=escape(sc.name),titleColor=open and ivory or muted,
			subtitle=escape(kind.verb or "Cross").."   ·   Agility "..sc.level.."   ·   +"..fmt(sc.xp).." XP   ·   "..sc.duration.."s",
			badge=open and paint("UNLOCKED","7FE3CC") or ("Lv "..sc.level),badgeColor=open and mint or ember,
			detail=escape(sc.description),
			lines={regionLocked and paint("Needs access to "..escape(AH.regionName(sc.region))..".","EF7D67") or nil},
			actions={{caption="Guide",name="Guide"..sc.id,fn=function() AH.guide({"anchor:Waypoint_Shortcut_"..sc.id.."_A","anchor:Waypoint_Shortcut_"..sc.id.."_B"},sc.name) end}}})
	end
	AH.companions("Agility")
end
function AH.regionName(id)
	local region=Data and type(Data.RegionById)=="table" and Data.RegionById[id]
	return type(region)=="table" and region.name or tostring(id or "the wilds")
end
-- Skill pets (Agility: Gustling from laps; Hunter: three trapped companions).
function AH.companions(skill)
	local pets={}
	for _,pet in ipairs(tbl(Data.Pets)) do if pet.skill==skill then table.insert(pets,pet) end end
	if #pets==0 then return end
	heading("RARE COMPANIONS")
	local owned={}
	for _,entry in ipairs(tbl(dget("pets"))) do if type(entry)=="table" and entry.id then owned[entry.id]=true end end
	for _,pet in ipairs(pets) do
		local itemId=pet.id.."Pet"
		local have=owned[pet.id] or count("items",itemId)>0
		local sources={}
		if skill=="Agility" then
			for _,drop in ipairs(tbl(Data.Agility.LapDrops)) do if drop.item==itemId then table.insert(sources,"any lap ("..chance(drop.chance)..")") end end
		else
			for _,creature in ipairs(Data.Hunter.Creatures) do
				for _,drop in ipairs(creature.drops) do if drop.item==itemId then table.insert(sources,escape(creature.name).." ("..chance(drop.chance)..")") end end
			end
		end
		card({name="Companion"..pet.id,item=itemId,locked=not have,iconSize=compactAtlas and 36 or 44,title=escape(pet.name),
			titleColor=have and safeColor(rarityHex(pet.rarity),ivory) or muted,subtitle=escape(pet.rarity).."   ·   "..escape(pet.ability or ""),
			badge=have and paint("OWNED","7FE3CC") or nil,badgeColor=mint,
			lines={"From: "..(#sources>0 and table.concat(sources,", ") or "—"),"Per level: "..statText(pet.perLevel)}})
	end
end

------------------------------------------------------------------------------
-- Hunt › Hunter
------------------------------------------------------------------------------
function AH.drawHunter()
	if not AH.ready() then dataMissing() return end
	local HU=Data.Hunter
	local hu=tbl(AH.state().hunter)
	local log=tbl(hu.log)
	local level=AH.level("Hunter")
	local stats=tbl(dget("stats"))
	local trapLuck=num(stats.trapLuck,0)
	local tiers,caughtTotal,known=0,0,0
	for _,c in ipairs(HU.Creatures) do
		local n=num(log[c.id],0)
		caughtTotal+=n
		if n>0 then known+=1 end
		for _,need in ipairs(HU.LogTiers) do if n>=need then tiers+=1 end end
	end
	tiers=num(hu.logTiers,tiers)
	local maxTraps=num(hu.maxTraps,HU.maxTraps(level))
	local traps=tbl(hu.traps)
	local hex=skillHex("Hunter")
	card({name="HunterSummary",icon=function(parent,size) return titleArt(parent,"Hunter",size,"Hunt") end,accent=rgb(hex),
		title="Tracker's log",titleColor=gold,subtitle="Hunter "..level.."   ·   "..fmt(caughtTotal).." catches   ·   "..known.." / "..#HU.Creatures.." creatures",
		badge="Lv "..level,badgeColor=rgb(lighten(hex,.3)),
		detail="Set snares, bird snares and box traps at hunting grounds (you can tend "..maxTraps.." at once; one more every 20 levels) and swing a net through swarms. Traps check every "..HU.TICK.."s and collapse after "..HU.MAX_TICKS.." empty checks.",
		lines={"Log milestones ("..table.concat(HU.LogTiers," / ").." catches of a creature): "..statText(HU.LogBonus).." each, permanently."..
			(tiers>0 and ("  Earned: "..statText(HU.LogBonus,tiers)..".") or ""),
			paint("⌖ Trap Luck "..fmt(trapLuck).."%","D9A35E").." raises every catch chance.   "..paint("☘ Hunting Fortune "..fmt(num(stats.huntingFortune,0)),"FFAA00").." adds primary drops."}})
	-- Traps in the field (snapshot; the HUD counter is live).
	if #traps>0 then
		local lines={}
		for _,trap in ipairs(traps) do
			if type(trap)=="table" then
				local c=HU.CreatureById[trap.creature]
				local method=c and HU.Methods[c.method]
				local stateText=trap.state=="caught" and paint("✦ caught!","7FE3CC") or trap.state=="collapsed" and paint("✕ collapsed","EF7D67")
					or paint("set  ("..num(trap.ticks,0).."/"..HU.MAX_TICKS.." checks)","A9BDC1")
				table.insert(lines,escape(method and method.name or "Trap").." · "..escape(c and c.name or tostring(trap.creature)).."   "..stateText)
			end
		end
		card({name="HunterTraps",motif="Hunt",title="Traps in the field",titleColor=gold,badge=#traps.." / "..maxTraps,badgeColor=ivory,lines=lines})
	end
	heading("HUNTER LOG    /    "..known.." OF "..#HU.Creatures.." RECORDED")
	for _,c in ipairs(HU.Creatures) do
		local n=num(log[c.id],0)
		local open=level>=c.level
		local method=HU.Methods[c.method]
		local kit
		for _,id in ipairs(tbl(HU.Kits[c.method])) do if count("items",id)>0 then kit=id break end end
		local reached,nextNeed,previous,labels=AH.milestones(n,HU.LogTiers)
		local drops={}
		for _,drop in ipairs(c.drops) do
			local def=itemDef(drop.item)
			local amount=drop.min==drop.max and tostring(drop.min) or (drop.min.."–"..drop.max)
			local text=paint(escape(itemName(drop.item)),itemHex(drop.item)).." "..amount.." ("..chance(drop.chance)..")"
			if def and def.kind=="pet" then text=paint("★ ","F3C66E")..text end
			table.insert(drops,text)
		end
		local kitLine=(kit and check or cross).." "..escape(itemName(kit or method.kit))..(kit and "" or paint("  (Trackers' Lodge)","A9BDC1"))
		card({name="Creature"..c.id,icon=function(parent,size) return itemGlyph(parent,{name=c.name,color=c.color},size,n==0) end,iconSize=compactAtlas and 36 or 44,
			title=escape(c.name),titleColor=n>0 and rgb(lighten(c.color,.35)) or (open and ivory or muted),
			subtitle="Hunter "..c.level.."   ·   "..escape(method.name).."   ·   "..escape(AH.regionName(c.region)).."   ·   +"..fmt(c.xp).." XP",
			badge=open and (fmt(n).." caught") or ("Lv "..c.level),badgeColor=open and ivory or ember,
			pips={total=#HU.LogTiers,filled=reached,color=safeColor(c.color,mint),labels=labels},
			bar=n>0 and {fraction=nextNeed and math.clamp((n-previous)/math.max(1,nextNeed-previous),0,1) or 1,color=gold,
				caption=nextNeed and (fmt(n).." / "..fmt(nextNeed).." to log tier "..numeral(reached+1)) or "HUNTER LOG COMPLETE"} or nil,
			lines={"Kit: "..kitLine..(open and ("   ·   "..chance(HU.catchChance(c,level,trapLuck))..(method.trap and " per check" or " per swing")) or ""),
				"Drops: "..table.concat(drops,", ")},
			actions={{caption="Guide",name="Guide"..c.id,fn=function() AH.guide({"anchor:Waypoint_Hunting_"..c.id,"region:"..c.region},c.name) end}}})
	end
	AH.companions("Hunter")
end

------------------------------------------------------------------------------
-- Ledger › Vendors: Skymark Exchange (Skymarks) and Trackers' Lodge (coins).
------------------------------------------------------------------------------
AH.vendorInfo={
	Agility={label="Skymark Exchange",where="Compass Quay, beside the Quay Rigging Run",anchor="Waypoint_SkymarkExchange",set="Windrunner"},
	Hunter={label="Trackers' Lodge",where="Meadow Reach, by the Hopper Warren",anchor="Waypoint_TrackersLodge",set="Thicketstalker"},
}
function AH.costText(cost)
	local parts={}
	for id,n in pairs(tbl(cost)) do
		local have=id=="coins" and num(state.coins,0) or count("items",id)
		local text=id=="coins" and (fmt(n).." coins") or (fmt(n).." "..escape(itemName(id)))
		table.insert(parts,{id=id,text=paint(text,have>=n and "F3C66E" or "EF7D67").."  "..paint("("..short(have)..")","8FA5AB")})
	end
	table.sort(parts,function(a,b) return (a.id=="coins" and 0 or 1)<(b.id=="coins" and 0 or 1) end)
	local out={}
	for _,p in ipairs(parts) do table.insert(out,p.text) end
	return table.concat(out,"  +  ")
end
function AH.vendorOpen(skill)
	local vendor=tbl(AH.state().vendor)
	local open=player:GetAttribute("SkillVendor") or vendor.skill
	local untilTime=num(player:GetAttribute("SkillVendorUntil"),nil) or num(vendor.openUntil,0)
	return open==skill and untilTime>AH.now(),untilTime
end
function AH.drawVendors()
	table.clear(AH.timers)
	AH.closesAt=nil
	if not AH.ready() then dataMissing() return end
	local order={"Agility","Hunter"}
	local names={}
	for i,skill in ipairs(order) do names[i]=AH.vendorInfo[skill].label end
	sectionBar(names,AH.vendorInfo[AH.vendor].label,function(name)
		for _,skill in ipairs(order) do if AH.vendorInfo[skill].label==name then AH.vendor=skill end end
		render()
	end,{small=true,prefix="Vendor"})
	local skill=AH.vendor
	local info=AH.vendorInfo[skill]
	local vendor=Data.SkillVendors[skill]
	local open,untilTime=AH.vendorOpen(skill)
	local hex=skillHex(skill)
	local purse=skill=="Agility" and (paint("✦ "..fmt(count("items",Data.Agility.MARK_ITEM)).." Skymarks","7FE3D0").."   ·   ") or ""
	purse..=paint("◆ "..fmt(num(state.coins,0)).." coins","F3C66E")
	if open then
		AH.closesAt=untilTime
		card({name="VendorStatus",motif="Ledger",accent=rgb(hex),title=escape(vendor.name),titleColor=gold,subtitle=info.where,
			badge=paint("OPEN","7FE3CC"),badgeColor=mint,lines={purse},
			after=function(body,nextOrder)
				local copy=para(body,"",nextOrder(),muted,compactAtlas and 13 or 14)
				copy.Name="Countdown"
				local fn=function(t) return "Counter closes in "..paint(AH.mmss(untilTime-t),"F3C66E").."   ·   step away and it stays open" end
				copy.Text=fn(AH.now())
				table.insert(AH.timers,{label=copy,fn=fn})
			end})
	else
		card({name="VendorStatus",motif="Ledger",accent=rgb(hex),title=escape(vendor.name),titleColor=gold,subtitle=info.where,
			badge=paint("CLOSED","EF7D67"),badgeColor=ember,
			detail="Visit the counter to trade: it stays open for "..math.floor(num(Data.SKILL_VENDOR_SECONDS,300)/60).." minutes after each visit. You can browse the stock here any time.",
			lines={purse},
			actions={{caption="Guide",primary=true,name="GuideVendor",fn=function() AH.guide({"anchor:"..info.anchor},vendor.name) end}}})
	end
	heading("STOCK    /    "..#vendor.shop.." WARES")
	for _,entry in ipairs(vendor.shop) do
		local def=itemDef(entry.item)
		if def then
			local have=count("items",entry.item)
			local unique=def.kind=="armor" or def.kind=="accessory" or def.category=="trap"
			local afford=true
			for id,n in pairs(tbl(entry.cost)) do
				if (id=="coins" and num(state.coins,0) or count("items",id))<n then afford=false end
			end
			local reason=nil
			if not open then reason="Visit the "..vendor.name.." to trade."
			elseif unique and have>0 then reason="You already own "..def.name.."."
			elseif not afford then reason="You can't afford the "..def.name.." yet." end
			local lines={"Cost: "..AH.costText(entry.cost)}
			local stockKey=Data.Systems and Data.Systems.Stock.key("sv",skill,entry.item) -- §33 daily stock
			local stock=Pages.SYS and stockKey and Pages.SYS.stockText(stockKey)
			if stock then table.insert(lines,stock) end
			local stockLeft=Pages.SYS and stockKey and Pages.SYS.stockLeft(stockKey)
			if stockLeft==0 and not reason then reason="Sold out for today." end
			if type(def.stats)=="table" then table.insert(lines,statText(def.stats)) end
			if type(def.buff)=="table" then table.insert(lines,"Buff: "..statText(def.buff.stats).."  for "..clock(def.buff.duration)) end
			if type(def.requires)=="table" then
				local levels=skillsOf(state)
				for need_skill,need in pairs(def.requires) do
					local lvl=levels[need_skill] and levels[need_skill].level or 1
					table.insert(lines,(lvl>=need and check or cross).." Requires "..escape(need_skill).." "..need)
				end
			end
			if def.hunterMethod then
				local method=Data.Hunter.Methods[def.hunterMethod]
				local prey={}
				for _,c in ipairs(Data.Hunter.Creatures) do if c.method==def.hunterMethod then table.insert(prey,escape(c.name).." ("..c.level..")") end end
				table.insert(lines,"Works on: "..table.concat(prey,", "))
				if method and not method.trap then table.insert(lines,"Nets catch on the spot; no trap slot used.") end
			end
			card({name="Ware"..entry.item,item=entry.item,iconSize=compactAtlas and 38 or 48,title=escape(def.name),titleColor=safeColor(rarityHex(def.rarity),ivory),
				subtitle=escape(def.rarity or "Common").."   ·   "..escape(kindLabel(def))..(def.set and ("   ·   "..escape(def.set).." set") or ""),
				badge=have>0 and (unique and paint("OWNED","7FE3CC") or ("×"..fmt(have))) or nil,badgeColor=unique and mint or ivory,
				detail=escape(def.description or ""),lines=lines,
				actions={{caption="Buy",primary=reason==nil,disabled=reason~=nil,reason=reason,name="Buy"..entry.item,
					fn=function() send("skillBuy",skill..":"..entry.item) end},
					-- §31: quantity picker (features.client.lua); stackable wares only.
					not unique and {caption="Buy ×…",disabled=reason~=nil,reason=reason,name="BuyQty"..entry.item,
					fn=function() UI.pickQuantity({verb="skillBuy",base=skill..":"..entry.item,name=def.name,unit=num(tbl(entry.cost).coins,0),amount=1,max=math.min(UI.affordLots(entry.cost),math.max(1,stockLeft or 64))}) end} or nil}})
		end
	end
	-- Set bonus: Windrunner (Exchange stock) or Thicketstalker (Workbench, from pelts).
	local set=Data.Sets and Data.Sets[info.set]
	if type(set)=="table" then
		local equipment=tbl(dget("equipment"))
		local worn,owned=0,0
		local lines={}
		for _,piece in ipairs(set.pieces) do
			local def=itemDef(piece)
			local has=count("items",piece)>0
			local on=false
			for _,slot in ipairs(gearSlots) do if equipment[slot]==piece then on=true end end
			if has then owned+=1 end
			if on then worn+=1 end
			local recipe=Data.Recipes and Data.Recipes[piece]
			local source=recipe and paint("  Workbench · Hunter "..num(recipe.level,1),"A9BDC1") or ""
			table.insert(lines,(has and check or cross).." "..escape(def and def.name or piece)..(on and paint("  worn","7FE3CC") or "")..source)
		end
		heading("SET BONUS    /    "..string.upper(set.name))
		card({name="SetBonus"..set.id,motif="Hero",accent=safeColor(set.color,gold),title=escape(set.name).." outfit",titleColor=safeColor(set.color,gold),
			subtitle=owned.." / "..#set.pieces.." owned   ·   "..worn.." worn",badge=worn>=#set.pieces and paint("ACTIVE","7FE3CC") or (worn.." / "..#set.pieces),
			badgeColor=worn>=#set.pieces and mint or muted,detail="Wear all four pieces: "..escape(set.text or "")..".",lines=lines})
	end
end
Pages.drawAgility,Pages.drawHunter,Pages.drawVendors=AH.drawAgility,AH.drawHunter,AH.drawVendors
end

------------------------------------------------------------------------------
-- Hero › Mastery: one perk tree per gathering skill and combat style (nodes
-- joined by their prerequisite lines; owned / available / open / locked),
-- the selected node's effects with a next-level preview, points and tokens,
-- respec and the capstone ability. Skills page milestones (titles, auras,
-- mantles) are drawn from here too. State lives in one table (local limit).
------------------------------------------------------------------------------
do
local MS={tree="Mining",node=nil,confirm=nil}
Pages.mastery=MS
function MS.data() return Data and type(Data.Mastery)=="table" and Data.Mastery or nil end
function MS.view() return tbl(tbl(depth()).mastery) end
function MS.treeView(id) return tbl(tbl(MS.view().trees)[id]) end
function MS.treeOfSkill(skill) local ma=MS.data() return ma and tbl(ma.TreeOfSkill)[skill] or nil end
MS.glyphs={xpBoost="✎",doubleYield="×2",tripleYield="×3",respawnSkip="↻",autoSmelt="♨",coinFind="¤",trapTick="⏱",rareFind="✧",
	firstStrike="⚡",execute="✖",arrowSave="➶",glyphSave="✐",manaThrift="✦",multishot="⇶",yieldMult="⇈"}
function MS.glyph(node)
	if node.ability then return "★" end
	for key in pairs(tbl(node.perks)) do return MS.glyphs[key] or "◆" end
	for key in pairs(tbl(node.stats)) do local def=tbl(tbl(Data.Stats)[key]) return type(def.symbol)=="string" and def.symbol or "◆" end
	return "◆"
end
-- Effect copy for a node at a level (stats + perks + capstone).
function MS.effects(node,level)
	local parts={}
	if level<=0 then return "" end
	if type(node.stats)=="table" then
		local text=statText(node.stats,level)
		if text~="" then table.insert(parts,text) end
	end
	for key,value in pairs(tbl(node.perks)) do
		local perk=tbl(tbl(MS.data().Perks)[key])
		local amount=num(value,0)*level
		local ok,text=pcall(string.format,tostring(perk.text or (key.." %s")),fmt(amount))
		table.insert(parts,paint(escape(ok and text or key),"9EE7D2"))
	end
	if type(node.ability)=="table" then
		table.insert(parts,paint(escape(tostring(node.ability.text or "")),"F9CC77"))
		table.insert(parts,"Lasts "..num(node.ability.duration,0).."s  ·  recharges "..num(node.ability.cooldown,0).."s")
	end
	return table.concat(parts,"  ·  ")
end
local stateLook={owned={"OWNED","7FE3CC"},partial={"LEARNING","F3C66E"},available={"AVAILABLE","F3C66E"},open={"NEED POINTS","A9BDC1"},locked={"LOCKED","E8806A"}}
-- Tree canvas: lines first, then node buttons on a 5 x 6 lattice.
function MS.canvas(tree,view)
	local width=contentWidth()
	local rows=0
	for _,n in ipairs(tree.nodes) do rows=math.max(rows,num(n.y,1)) end
	local rowH=compactAtlas and 62 or 74
	local size=compactAtlas and UI.TOUCH or 50
	local height=rows*rowH+16
	local holder=container(height)
	holder.Name="MasteryCanvas"
	holder.BackgroundColor3=track
	holder.BackgroundTransparency=.35
	make("UICorner",holder,{CornerRadius=UDim.new(0,12)})
	make("UIStroke",holder,{Color=UI.line,Thickness=1})
	local colW=(width-16)/5
	local function center(n) return 8+(num(n.x,3)-.5)*colW,8+(num(n.y,1)-.5)*rowH end
	local levels,states=tbl(view.nodes),tbl(view.states)
	local hex=type(tree.color)=="string" and #tree.color==6 and tree.color or "F3C66E"
	for _,n in ipairs(tree.nodes) do
		for _,reqId in ipairs(tbl(n.requires)) do
			local req=tree.NodeById[reqId]
			if req then
				local x1,y1=center(req)
				local x2,y2=center(n)
				local dx,dy=x2-x1,y2-y1
				local lit=num(levels[n.id],0)>0 and num(levels[reqId],0)>0
				local ready=num(levels[reqId],0)>0
				make("Frame",holder,{Name="Link",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset((x1+x2)/2,(y1+y2)/2),
					Size=UDim2.fromOffset(math.sqrt(dx*dx+dy*dy),lit and 3 or 2),Rotation=math.deg(math.atan2(dy,dx)),BorderSizePixel=0,
					BackgroundColor3=lit and rgb(hex) or (ready and UI.brass or UI.line),BackgroundTransparency=lit and 0 or .25})
			end
		end
	end
	for _,n in ipairs(tree.nodes) do
		local cx,cy=center(n)
		local st=type(states[n.id])=="string" and states[n.id] or (num(levels[n.id],0)>0 and "partial" or "locked")
		local have=math.floor(num(levels[n.id],0))
		local on=MS.node==n.id
		local b=make("TextButton",holder,{Name="MasteryNode"..n.id,Text="",AutoButtonColor=false,Selectable=true,BorderSizePixel=0,
			Position=UDim2.fromOffset(cx-size/2,cy-size/2),Size=UDim2.fromOffset(size,size),ZIndex=2,
			BackgroundColor3=(st=="owned" or st=="partial") and rgb(hex) or (st=="available" and slate or (st=="open" and deep or track))})
		make("UICorner",b,{CornerRadius=UDim.new(0,n.ability and size//2 or 10)})
		UI.sheen(b,1,.7)
		make("UIStroke",b,{Color=on and ivory or (st=="available" and gold or (n.ability and gold or UI.line)),Thickness=on and 2.5 or (st=="available" and 2 or 1),Transparency=st=="locked" and .4 or 0})
		local glyph=label(b,MS.glyph(n),0,0,full,size-14,UI.heavy,compactAtlas and 15 or 18,st=="locked" and muted or UI.white)
		glyph.Size=UDim2.new(1,0,1,-12)
		glyph.TextXAlignment=Enum.TextXAlignment.Center
		glyph.TextStrokeTransparency=.4
		glyph.TextStrokeColor3=deep
		glyph.ZIndex=3
		local pip=label(b,have.."/"..num(n.max,1),0,0,full,12,UI.heavy,10,st=="locked" and muted or ivory)
		pip.Position=UDim2.new(0,0,1,-14)
		pip.TextXAlignment=Enum.TextXAlignment.Center
		pip.TextStrokeTransparency=.3
		pip.TextStrokeColor3=deep
		pip.ZIndex=3
		pressable(b)
		b.Activated:Connect(function()
			MS.node=if MS.node==n.id then nil else n.id
			render()
		end)
	end
	return holder
end
-- Selected node: effects now and at the next level, gates, unlock.
function MS.nodeCard(tree,view,node)
	local levels,states=tbl(view.nodes),tbl(view.states)
	local have=math.floor(num(levels[node.id],0))
	local st=type(states[node.id])=="string" and states[node.id] or "locked"
	local look=stateLook[st] or stateLook.locked
	local lines={}
	if have>0 then table.insert(lines,"Now: "..MS.effects(node,have)) end
	if have<num(node.max,1) then table.insert(lines,(have>0 and "Next: " or "Unlocks: ")..MS.effects(node,have+1)) end
	local reqs={}
	for _,id in ipairs(tbl(node.requires)) do
		local req=tree.NodeById[id]
		if req then table.insert(reqs,(num(levels[id],0)>0 and check or cross).." "..escape(req.name)) end
	end
	if #reqs>0 then table.insert(lines,"Requires any: "..table.concat(reqs,"  ")) end
	local skillLevel=num(tbl(tbl(dget("skills"))[tree.skill]).level,1)
	table.insert(lines,(skillLevel>=num(node.level,1) and check or cross).." "..escape(tree.skill).." "..num(node.level,1).."   ·   "..num(node.cost,1).." point"..(num(node.cost,1)==1 and "" or "s").." per level")
	local reason=nil
	if st=="owned" then reason=node.name.." is complete."
	elseif st~="available" then reason=if st=="locked" then "Unlock a linked node first." elseif skillLevel<num(node.level,1) then "Requires "..tree.skill.." "..num(node.level,1).."." else "Not enough mastery points." end
	card({name="MasteryNodeDetail",accent=safeColor(tree.color,gold),motif="Hero",title=escape(node.name),titleColor=node.ability and gold or ivory,
		subtitle=(node.ability and "Capstone ability" or "Level "..have.." / "..num(node.max,1)).."   ·   "..escape(tree.name),
		badge=paint(look[1],look[2]),badgeColor=rgb(look[2]),lines=lines,
		actions={{caption=have>0 and "Level up" or "Unlock",primary=reason==nil,disabled=reason~=nil,reason=reason,name="MasteryUnlock",
			fn=function() send("masteryUnlock",tree.id..":"..node.id) end}}})
end
function MS.draw()
	local ma=MS.data()
	if not ma or type(ma.TreeById)~="table" then dataMissing() return end
	if not ma.TreeById[MS.tree] then MS.tree=ma.TreeOrder[1] end
	local tree=ma.TreeById[MS.tree]
	local view=MS.view()
	local tv=MS.treeView(tree.id)
	local tokens=tbl(view.tokens)
	local synced=next(view)~=nil
	card({name="MasterySummary",motif="Hero",title="Skill Mastery",titleColor=gold,badge=if synced then nil else "SYNCING",badgeColor=muted,
		subtitle=fmt(num(tokens.free,0)).." Mastery Token"..(num(tokens.free,0)==1 and "" or "s").." free   ·   "..fmt(num(tokens.earned,0)).." earned",
		detail="Each tree draws on its skill: 1 point per level above "..num(ma.POINT_START_LEVEL,10)..", +1 per "..fmt(num(ma.POST_MAX_STEP,1000000))
			.." XP beyond 99. Tokens from collection tiers "..table.concat(ma.TOKEN_TIERS or {},"/").." fill any tree."})
	local names={}
	for _,id in ipairs(ma.TreeOrder) do table.insert(names,id) end
	sectionBar(names,MS.tree,function(name) MS.tree=name;MS.node=nil;MS.confirm=nil;render() end,{small=true,prefix="MasteryTree",maxPer=compactAtlas and 4 or 8})
	local hex=type(tree.color)=="string" and #tree.color==6 and tree.color or "F3C66E"
	local available,spent,earned=num(tv.available,0),num(tv.spent,0),num(tv.earned,0)
	local cost=num(tv.respecCost,0)
	local actions={}
	if MS.confirm==tree.id then
		table.insert(actions,{caption="Keep",name="MasteryRespecCancel",fn=function() MS.confirm=nil;render() end})
		table.insert(actions,{caption="Reset "..fmt(cost),name="MasteryRespecConfirm",primary=true,disabled=num(state.coins,0)<cost,reason="Resetting costs "..fmt(cost).." coins.",
			fn=function() MS.confirm=nil;send("masteryRespec",tree.id) end})
	else
		table.insert(actions,{caption="Respec",name="MasteryRespec",disabled=spent<=0,reason="Nothing to reset yet.",fn=function() MS.confirm=tree.id;render() end})
	end
	card({name="MasteryTree",accent=rgb(hex),icon=function(parent,size) return titleArt(parent,tree.skill,size,"Hero") end,
		title=escape(tree.name),titleColor=rgb(lighten(hex,.25)),subtitle=escape(tree.skill).." mastery   ·   "..fmt(spent).." spent / "..fmt(earned).." earned",
		badge=fmt(available).." pts",badgeColor=available>0 and gold or muted,detail=escape(tree.blurb or ""),
		lines={MS.confirm==tree.id and paint("Reset refunds every point for "..fmt(cost).." coins (the price grows with each reset).","F9CC77") or ("Respec: "..fmt(cost).." coins")},
		actions=actions})
	heading(string.upper(tree.name).."    /    TAP A NODE")
	MS.canvas(tree,tv)
	local node=MS.node and tree.NodeById[MS.node]
	if node then MS.nodeCard(tree,tv,node) end
	-- Capstone ability.
	local capstone=tree.capstone and tree.NodeById[tree.capstone]
	if capstone then
		local owned=tv.capstone==true
		local cooldown,active=num(tv.cooldown,0),num(tv.active,0)
		local ability=tbl(capstone.ability)
		local reason=if not owned then "Unlock "..capstone.name.." first." elseif cooldown>0 then capstone.name.." recharges in "..math.ceil(cooldown).."s." else nil
		heading("CAPSTONE    /    "..string.upper(capstone.name))
		card({name="MasteryAbility",motif="Hero",accent=gold,title=escape(capstone.name),titleColor=gold,
			subtitle=active>0 and paint("ACTIVE · "..math.ceil(active).."s left","7FE3CC") or (owned and (cooldown>0 and ("Recharging · "..math.ceil(cooldown).."s") or "Ready") or "Locked"),
			badge=owned and (cooldown>0 and (math.ceil(cooldown).."s") or "READY") or "LOCKED",badgeColor=owned and (cooldown>0 and muted or mint) or ember,
			detail=escape(tostring(ability.text or "")),
			bar=owned and cooldown>0 and {fraction=1-math.clamp(cooldown/math.max(1,num(ability.cooldown,1)),0,1),color=gold,caption="Recharging"} or nil,
			actions={{caption="Activate",primary=reason==nil,disabled=reason~=nil,reason=reason,name="MasteryActivate",fn=function() send("ability",tree.id) end}}})
	end
	-- Worn mantle (skillcape) summary.
	local cape=type(view.cape)=="string" and view.cape or nil
	local capes=tbl(view.capes)
	if cape or #capes>0 then
		local perk=cape and type(ma.capePerk)=="function" and ma.capePerk(cape) or nil
		card({name="MasteryMantle",motif="Hero",title=cape and ("Mantle of the "..escape(tostring(skillDef(cape).title or cape))) or "Mantles",titleColor=gold,
			subtitle=#capes.." mantle"..(#capes==1 and "" or "s").." earned",badge=cape and "WORN" or nil,badgeColor=mint,
			detail=cape and ("Worn mantle perk: "..statText(perk,1)) or "Wear a mantle from a level 99 skill on the Skills page."})
	end
end
-- Skills page: milestone list (titles, auras, mantle) with wear actions.
function MS.milestones(skill,info)
	local ma=MS.data()
	if not ma or type(ma.milestones)~="function" then return end
	local ok,list=pcall(ma.milestones,skill)
	if not ok or type(list)~="table" then return end
	local level=num(tbl(info).level,1)
	local view=MS.view()
	local items={}
	for _,m in ipairs(list) do
		local extra=m.stats and ("  "..statText(m.stats,1)) or ""
		table.insert(items,{text="Lv "..m.level.."  ·  "..escape(m.text)..extra,met=level>=m.level,amount="+"..fmt(num(m.coins,0)).." c"})
	end
	local tree=MS.treeOfSkill(skill)
	local actions={}
	if tree then
		table.insert(actions,{caption="Mastery",name="SkillMastery"..skill,fn=function()
			MS.tree=tree;MS.node=nil;sectionOf.Hero="Mastery";scroll.CanvasPosition=Vector2.zero;render() end})
	end
	if level>=num(ma.MilestoneLevels and ma.MilestoneLevels[1],10) then
		local worn=view.title==skill
		table.insert(actions,{caption=worn and "Untitle" or "Title",name="SkillTitle"..skill,fn=function() send("masteryWear","title:"..(worn and "" or skill)) end})
	end
	if level>=maxLevel() then
		local worn=view.cape==skill
		table.insert(actions,{caption=worn and "Unwear" or "Mantle",name="SkillCape"..skill,primary=not worn,fn=function() send("masteryWear","cape:"..(worn and "" or skill)) end})
	elseif level>=50 then
		local worn=view.aura==skill
		table.insert(actions,{caption=worn and "No aura" or "Aura",name="SkillAura"..skill,fn=function() send("masteryWear","aura:"..(worn and "" or skill)) end})
	end
	local tv=tree and MS.treeView(tree) or EMPTY
	local title=tbl(view.titles)[skill]
	heading(string.upper(skill).."    /    MILESTONES")
	card({name="SkillMilestones",motif="Hero",title=type(title)=="string" and escape(title) or "No title yet",titleColor=gold,
		subtitle=tree and (fmt(num(tv.available,0)).." mastery points to spend in the "..escape(tostring(tbl(ma.TreeById[tree]).name or tree))) or "Titles, auras and a mantle at 99",
		after=function(body,nextOrder) UI.checklist(body,nextOrder,nil,items) end,actions=actions})
end
-- Skills summary line and tile marker.
function MS.summary()
	local view=MS.view()
	if next(view)==nil then return nil end
	local free=0
	for _,tv in pairs(tbl(view.trees)) do free=math.max(free,num(tbl(tv).available,0)) end
	local cape=type(view.cape)=="string" and view.cape or nil
	return "Mastery: "..fmt(num(tbl(view.tokens).free,0)).." tokens free"..(free>0 and ("  ·  up to "..fmt(free).." points to spend") or "")
		..(cape and ("  ·  wearing the "..escape(cape).." mantle") or "")
end
function MS.wornCape() local cape=MS.view().cape return type(cape)=="string" and cape or nil end
Pages.drawMastery=MS.draw
end

------------------------------------------------------------------------------
-- Workshop › Garden (Farming Depth team): the Verdant Garden. A summary card
-- (garden level, plots, Marks, Dust, bulk harvest/water) and five views:
-- Plots (a 12-tile grid with stage, timer, water/compost/blight/pest chips; the
-- selected plot opens a detail card with its actions and the seed picker),
-- Visitors (requests with have/need checklists, rewards, accept/decline),
-- Composter (matter, output, upgrade, feed cards), Milestones (per-crop tiers)
-- and Shop (seeds, hoes, Rootwarden set, charm, plot skins). Server state:
-- snapshot.garden (server Garden.state); static data: Data.Garden. Verbs:
-- plant "i:seed", harvestPlot/waterPlot "i"|"all", fertilise/treatPlot/clearPest/
-- clearPlot "i", compost "item:n", compostClaim, composterUpgrade,
-- visitorAccept/visitorDecline "id", gardenBuy "shopId", gardenSkin "skin".
-- Countdown labels tick in place every second while the page is open.
------------------------------------------------------------------------------
do
local GD={view="Plots",selected=nil,timers={},drawnAt=0,VIEWS={"Plots","Visitors","Composter","Milestones","Shop"},hex="5FBF77"}
Pages.GD=GD
function GD.ready() return Data and type(Data.Garden)=="table" and type(Data.Garden.Crops)=="table" end
function GD.state() return tbl(state.garden) end
function GD.span(seconds)
	seconds=math.max(0,math.floor(num(seconds,0)))
	if seconds>=3600 then return (seconds//3600).."h "..string.format("%02d",(seconds%3600)//60).."m" end
	if seconds>=60 then return (seconds//60).."m "..string.format("%02d",seconds%60).."s" end
	return seconds.."s"
end
-- A countdown label: fn(elapsed) → text; elapsed counts from the last draw.
function GD.timer(label,fn)
	table.insert(GD.timers,{label=label,fn=fn})
	label.Text=fn(0)
	return label
end
function GD.farming() local info=skillsOf(state).Farming return info and num(info.level,1) or 1 end
function GD.costText(cost,haveCheck)
	local parts={}
	for id,n in pairs(tbl(cost)) do
		n=num(n,0)
		local text=if id=="coins" then fmt(n).." coins" else fmt(n).." "..escape(itemName(id))
		if haveCheck then
			local have=if id=="coins" then num(state.coins,0) else count("items",id)
			text=(if have>=n then check else cross).." "..text
		end
		table.insert(parts,text)
	end
	table.sort(parts)
	return table.concat(parts,"   ")
end
function GD.afford(cost)
	for id,n in pairs(tbl(cost)) do
		local have=if id=="coins" then num(state.coins,0) else count("items",id)
		if have<num(n,0) then return false end
	end
	return true
end
-- Plot record from the snapshot (tolerates partial / malformed data).
function GD.plot(g,i)
	local raw=tbl(tbl(g.plots)[i])
	local G=Data.Garden
	local crop=type(raw.crop)=="string" and G.CropById[raw.crop] or nil
	return {index=i,unlocked=raw.unlocked==true,crop=crop,stage=math.clamp(math.floor(num(raw.stage,0)),0,G.STAGES),ripe=raw.ripe==true,
		remaining=num(raw.remaining,nil),fraction=math.clamp(num(raw.fraction,0),0,1),watered=num(raw.watered,0),compost=raw.compost==true,
		treated=raw.treated==true,sick=raw.sick==true,dead=raw.dead==true,pest=type(raw.pest)=="string" and raw.pest or nil,deathIn=num(raw.deathIn,nil)}
end
function GD.status(p)
	if not p.unlocked then return "Locked","8A9BA3" end
	if not p.crop then return "Empty","A9BDC1" end
	if p.dead then return "Withered","9A948A" end
	if p.sick then return "Blighted","E8806A" end
	if p.ripe then return "Ripe!","F3C66E" end
	return Data.Garden.STAGE_NAMES[math.max(1,p.stage)] or "Growing","9EE7D2"
end
function GD.chips(p)
	local chips={}
	if p.watered>0 then table.insert(chips,paint("💧","8FD3FF")) end
	if p.compost then table.insert(chips,paint("❖","C9A26B")) end
	if p.treated then table.insert(chips,paint("✚","9FD8A6")) end
	if p.pest then table.insert(chips,paint("✸ pest","E8806A")) end
	return table.concat(chips," ")
end
function GD.select(i)
	GD.selected=if GD.selected==i then nil else i
	render()
end
function GD.summary(g)
	local G=Data.Garden
	local level=math.clamp(math.floor(num(g.level,1)),1,G.MAX_LEVEL)
	local xp,floor,nextAt=num(g.xp,0),num(g.floor,0),num(g.nextAt,nil)
	local unlocked=math.clamp(math.floor(num(g.unlocked,G.BASE_PLOTS)),0,G.MAX_PLOTS)
	local ripe,waiting=0,#tbl(g.visitors)
	for i=1,G.MAX_PLOTS do if GD.plot(g,i).ripe then ripe+=1 end end
	local rate=num(g.rate,1)
	card({name="GardenSummary",item=G.CropById.Herb and "Herb" or nil,accent=rgb(GD.hex),title="Verdant Garden",titleColor=gold,
		subtitle="Garden level "..level.."   ·   "..unlocked.."/"..G.MAX_PLOTS.." plots   ·   "..paint("✦ "..fmt(count("items",G.MARK)).." Marks","5FBF77").."   ·   "..fmt(count("items",G.DUST)).." Bloom Dust",
		badge="Lv "..level,badgeColor=rgb(lighten(GD.hex,.3)),
		detail="Plant seeds in your garden islet beside home. Crops grow while you are away; water and compost speed them up, Blightward Salve stops blight, and visitors trade Verdant Marks for your harvest.",
		lines={(if type(g.nextPlot)=="string" then "Next plot: "..escape(g.nextPlot).."." else "Every plot is open.").."   ·   Growth "..math.floor(rate*100+.5).."%"..(if g.setActive==true then "  ("..paint("Rootwarden set","9BD77E")..")" else ""),
			ripe.." ripe   ·   "..waiting.." visitor"..(if waiting==1 then "" else "s").." waiting   ·   "..fmt(num(g.served,0)).." served"},
		bar={fraction=if nextAt then math.clamp((xp-floor)/math.max(1,nextAt-floor),0,1) else 1,color=rgb(GD.hex),
			caption=if nextAt then fmt(xp-floor).." / "..fmt(nextAt-floor).." garden XP" else "Garden level maxed"},
		actions={{caption="Harvest all",primary=ripe>0,disabled=ripe==0,reason="Nothing is ripe yet.",name="GardenHarvestAll",fn=function() send("harvestPlot","all") end},
			{caption="Water all",name="GardenWaterAll",fn=function() send("waterPlot","all") end}}})
end
function GD.drawPlots(g)
	local G=Data.Garden
	if GD.selected then GD.drawDetail(g,GD.plot(g,GD.selected)) end
	heading("PLOTS    /    TAP A PLOT TO TEND IT")
	local width=contentWidth()
	local columns=width>=690 and 4 or (width>=400 and 3 or 2)
	local cellHeight=compactAtlas and 104 or 118
	local grid=gridHolder(UDim2.new(1/columns,-6,0,cellHeight),6)
	for i=1,G.MAX_PLOTS do
		local p=GD.plot(g,i)
		local status,statusHex=GD.status(p)
		local b=tile(grid,"Plot"..i,i,function() GD.select(i) end)
		local on=GD.selected==i
		make("UIStroke",b,{Color=on and gold or rgb(statusHex),Transparency=on and 0 or .55,Thickness=on and 2 or 1})
		if not p.unlocked then b.BackgroundTransparency=.45 end
		label(b,"#"..i,10,8,UDim.new(0,30),18,UI.heavy,12,muted)
		local name=label(b,p.crop and escape(itemName(p.crop.id)) or (p.unlocked and "Empty plot" or "Locked"),36,8,UDim.new(1,-46),18,UI.heavy,compactAtlas and 13 or 14,
			p.crop and rgb(p.crop.tint) or muted)
		name.RichText=true
		local stat=label(b,paint(status,statusHex).."  "..GD.chips(p),10,compactAtlas and 30 or 32,UDim.new(1,-20),18,bold,12,ivory)
		stat.RichText=true
		if p.crop and not p.dead then
			local bar=progress(b,p.fraction,rgb(p.crop.tint),nil,compactAtlas and 8 or 10)
			bar.Position=UDim2.new(0,10,0,compactAtlas and 56 or 60)
			bar.Size=UDim2.new(1,-20,0,compactAtlas and 8 or 10)
		end
		local timer=label(b,"",10,compactAtlas and 72 or 80,UDim.new(1,-20),18,bold,12,muted)
		timer.Name="PlotTimer"
		if p.crop and p.remaining and not p.ripe then
			local remaining=p.remaining
			GD.timer(timer,function(elapsed) return "Ripe in "..GD.span(remaining-elapsed) end)
		elseif p.sick and p.deathIn then
			local left=p.deathIn
			GD.timer(timer,function(elapsed) return "Withers in "..GD.span(left-elapsed) end)
		else
			timer.Text=if p.ripe then "Ready to harvest" elseif p.dead then "Clear to replant" elseif p.unlocked then "Plant a seed" else "Unlock with garden level"
		end
	end
end
function GD.seedCards(i)
	local G=Data.Garden
	local farming=GD.farming()
	heading("SEEDS    /    CHOOSE WHAT TO PLANT IN PLOT "..i)
	for _,c in ipairs(G.Crops) do
		local have=count("items",c.seed)
		local locked=farming<c.level
		local reason=(locked and ("Needs Farming "..c.level..".")) or (have<1 and "No seeds. Buy them in the Shop view.") or nil
		card({name="Seed"..c.seed,item=c.seed,title=escape(itemName(c.seed)),titleColor=rgb(c.tint),locked=locked,
			subtitle="×"..fmt(have).."   ·   Farming "..c.level.."   ·   ripens in "..GD.span(c.grow).."   ·   base yield "..c.yield,
			lines={"+"..fmt(c.xp).." Farming XP, +"..c.gxp.." garden XP per harvest   ·   blight risk "..math.floor(c.disease*100).."%"},
			actions={{caption="Plant",primary=reason==nil,disabled=reason~=nil,reason=reason,name="Plant"..c.seed,fn=function() send("plant",i..":"..c.seed) end}}})
	end
end
function GD.drawDetail(g,p)
	local G=Data.Garden
	local i=p.index
	local status,statusHex=GD.status(p)
	local compost,salve=count("items",G.COMPOST),count("items",G.SALVE)
	local acts={}
	local function act(caption,name,verb,primary,disabled,reason)
		table.insert(acts,{caption=caption,name=name,primary=primary,disabled=disabled,reason=reason,fn=function() send(verb,tostring(i)) end})
	end
	local lines={}
	if not p.unlocked then
		card({name="PlotDetail",motif="Workshop",title="Plot "..i.."  ·  Locked",titleColor=muted,detail="Unlock more plots with garden levels and Farming levels. "..(if type(g.nextPlot)=="string" then "Next: "..escape(g.nextPlot).."." else "")})
		return
	end
	if p.pest then act("Swat pest","PlotSwat","clearPest",true) end
	if p.dead then act("Clear","PlotClear","clearPlot",true)
	elseif p.sick then act("Treat","PlotTreat","treatPlot",true,salve<1,"You need a Blightward Salve (Cauldron, Alchemy 12, or the Shop).")
	elseif p.ripe then act("Harvest","PlotHarvest","harvestPlot",true)
	elseif p.crop then
		act("Water","PlotWater","waterPlot",p.watered<=0,p.watered>0,"Still damp.")
		if not p.compost then act("Fertilise","PlotFertilise","fertilise",false,compost<1,"You need Rich Compost from the composter.") end
		if not p.treated and #acts<3 then act("Treat","PlotTreat","treatPlot",false,salve<1,"You need a Blightward Salve.") end
	else
		if not p.compost then act("Fertilise","PlotFertilise","fertilise",false,compost<1,"You need Rich Compost from the composter.") end
		if not p.treated then act("Treat","PlotTreat","treatPlot",false,salve<1,"You need a Blightward Salve.") end
	end
	while #acts>3 do table.remove(acts) end
	if p.crop then
		table.insert(lines,"Stage "..p.stage.."/"..G.STAGES.."   ·   "..math.floor(p.fraction*100).."% grown"..(if p.watered>0 then "   ·   watered for "..GD.span(p.watered) else ""))
		if p.pest then table.insert(lines,paint("A "..escape(p.pest).." is nibbling this crop: −"..math.floor(G.PEST_PENALTY*100).."% yield until you swat it.","E8806A")) end
		if p.sick then table.insert(lines,paint("Blight halts growth. Treat it before it withers.","E8806A")) end
	end
	table.insert(lines,(if p.compost then "Fertilised (+"..math.floor(G.COMPOST_BOOST*100).."% growth)" else "Not fertilised").."   ·   "..(if p.treated then "Treated (blight-proof)" else "Untreated"))
	card({name="PlotDetail",item=p.crop and p.crop.id or nil,motif=(not p.crop) and "Workshop" or nil,accent=rgb(statusHex),
		title="Plot "..i.."  ·  "..(if p.crop then escape(itemName(p.crop.id)) else "Empty"),titleColor=p.crop and rgb(p.crop.tint) or ivory,
		subtitle=paint(status,statusHex).."   ·   "..fmt(compost).." compost   ·   "..fmt(salve).." salve",lines=lines,
		bar=p.crop and not p.dead and {fraction=p.fraction,color=rgb(p.crop.tint),caption=if p.ripe then "Ripe" elseif p.remaining then "Ripe in "..GD.span(p.remaining) else status} or nil,
		actions=acts})
	if p.crop and not p.dead then
		card({name="PlotUprootCard",motif="Workshop",title="Uproot plot "..i,titleColor=muted,detail="Pull the crop to free the plot. The seed is lost.",
			actions={{caption="Uproot",name="PlotUproot",fn=function() send("clearPlot",tostring(i)) end}}})
	end
	if not p.crop then GD.seedCards(i) end
end
function GD.drawVisitors(g)
	local G=Data.Garden
	local visitors=tbl(g.visitors)
	local cap=num(g.visitorCap,G.visitorCap(num(g.level,1)))
	local summary=card({name="VisitorQueue",motif="Journal",title="Visitors  ·  "..#visitors.."/"..cap,titleColor=gold,
		detail="Islanders stop by every "..(G.VISITOR_INTERVAL//60).." minutes (while you are away too, until the bench is full) and trade for your crops."})
	if num(g.nextVisitorIn,nil) then
		local nextIn=num(g.nextVisitorIn,0)
		local copy=para(summary:FindFirstChild("Body"),"",99,muted,12)
		copy.Name="VisitorCountdown"
		GD.timer(copy,function(elapsed) return "Next visitor in "..GD.span(nextIn-elapsed) end)
	end
	for _,raw in ipairs(visitors) do
		local v=tbl(raw)
		local def=type(v.npc)=="string" and G.VisitorById[v.npc] or nil
		local id=math.floor(num(v.id,0))
		if def and id>0 then
			local rarity=G.VisitorRarity[def.rarity] or G.VisitorRarity.Common
			local rarityHexes={Common="FFFFFF",Uncommon="55FF55",Rare="5555FF",Legendary="FFAA00"}
			local checks,ready={},true
			for crop,n in pairs(tbl(v.wants)) do
				n=num(n,0)
				if type(crop)=="string" and itemDef(crop) then
					local have=count("items",crop)
					if have<n then ready=false end
					table.insert(checks,{text=fmt(n).." "..escape(itemName(crop)),met=have>=n,amount=fmt(have).."/"..fmt(n)})
				end
			end
			if #checks==0 then ready=false end
			local rewards={fmt(num(v.coins,0)).." coins",fmt(num(v.marks,0)).." Verdant Marks",fmt(num(v.gxp,0)).." garden XP",fmt(num(v.xp,0)).." Farming XP"}
			for item,n in pairs(tbl(v.items)) do if itemDef(item) then table.insert(rewards,paint(fmt(num(n,1)).." "..escape(itemName(item)),"F7B2D9")) end end
			card({name="Visitor"..id,motif="Journal",accent=rgb(def.color),title=escape(def.name),titleColor=rgb(def.color),
				subtitle=paint(def.rarity,rarityHexes[def.rarity] or "FFFFFF").."   ·   ×"..rarity.mult.." rewards",detail="“"..escape(def.line).."”",
				before=function(body,nextOrder) UI.checklist(body,nextOrder,"REQUEST",checks) end,
				lines={"Rewards: "..table.concat(rewards,"   ·   ")},
				actions={{caption="Accept",primary=ready,disabled=not ready,reason="You need every requested crop.",name="Accept"..id,fn=function() send("visitorAccept",tostring(id)) end},
					{caption="Decline",name="Decline"..id,fn=function() send("visitorDecline",tostring(id)) end}}})
		end
	end
	if #visitors==0 then row("No visitors yet","Visitors arrive at your garden islet over time. Keep crops in your satchel to fill their requests.") end
end
function GD.drawComposter(g)
	local G=Data.Garden
	local c=tbl(g.composter)
	if c.unlocked~=true then
		card({name="Composter",motif="Workshop",title="Composter  ·  locked",titleColor=muted,detail="The composter opens at garden level "..G.COMPOSTER_LEVEL..". Harvest crops and serve visitors to earn garden XP."})
		return
	end
	local upgrade=math.clamp(math.floor(num(c.upgrade,0)),0,#G.ComposterUpgrades)
	local nextUp=G.ComposterUpgrades[upgrade+1]
	local matter,cap,out,dust=num(c.matter,0),math.max(1,num(c.cap,G.matterCap(upgrade))),num(c.out,0),num(c.dust,0)
	local card_=card({name="Composter",item=G.COMPOST,title="Composter  ·  tier "..upgrade,titleColor=gold,
		subtitle=fmt(out).." "..escape(itemName(G.COMPOST)).." and "..fmt(dust).." "..escape(itemName(G.DUST)).." ready",
		detail="Feed crops and organic drops. Every "..GD.span(num(c.interval,G.COMPOST_SECONDS)).." the composter turns "..G.COMPOST_MATTER.." matter into one Rich Compost; every "..G.DUST_EVERY.."th compost leaves Bloom Dust.",
		bar={fraction=math.clamp(matter/cap,0,1),color=rgb("8C6A4A"),caption=fmt(matter).." / "..fmt(cap).." matter"},
		lines={if nextUp then "Next upgrade: "..GD.costText({BloomDust=nextUp.dust,VerdantMark=nextUp.marks},true).."   (−12% time, +1,500 matter)" else "Fully upgraded."},
		actions={{caption="Collect",primary=out>0 or dust>0,disabled=out<1 and dust<1,reason="Nothing has finished composting yet.",name="CompostCollect",fn=function() send("compostClaim") end},
			{caption="Upgrade",disabled=nextUp==nil or not GD.afford({BloomDust=nextUp.dust,VerdantMark=nextUp.marks}),reason=if nextUp then "You need more Bloom Dust or Verdant Marks." else "Fully upgraded.",
				name="CompostUpgrade",fn=function() send("composterUpgrade") end}}})
	if num(c.nextIn,nil) then
		local nextIn=num(c.nextIn,0)
		local copy=para(card_:FindFirstChild("Body"),"",99,muted,12)
		copy.Name="CompostCountdown"
		GD.timer(copy,function(elapsed) return "Next compost in "..GD.span(nextIn-elapsed) end)
	end
	heading("FEED    /    MATTER PER ITEM")
	local any=false
	local feedable={}
	for _,crop in ipairs(G.Crops) do table.insert(feedable,crop.id) end
	for id in pairs(G.ORGANIC_EXTRA) do table.insert(feedable,id) end
	table.sort(feedable)
	for _,id in ipairs(feedable) do
		local have=count("items",id)
		if have>0 and itemDef(id) then
			any=true
			local value=G.organic(id)
			card({name="Feed"..id,item=id,title=escape(itemName(id)),titleColor=rgb(itemHex(id)),subtitle="×"..fmt(have).."   ·   "..value.." matter each",
				actions={{caption="Feed 10",disabled=have<10,reason="You have fewer than 10.",name="Feed10"..id,fn=function() send("compost",id..":10") end},
					{caption="Feed all",primary=true,name="FeedAll"..id,fn=function() send("compost",id..":"..math.min(have,9999)) end}}})
		end
	end
	if not any then row("Nothing to compost","Crops, Beast Hide, Pest Chitin and logs make good matter.") end
end
function GD.drawMilestones(g)
	local G=Data.Garden
	local ms=tbl(g.milestones)
	card({name="MilestoneSummary",motif="Hero",title="Crop milestones",titleColor=gold,
		detail="Every garden harvest counts toward its crop's milestones. Each tier pays coins and garden XP, adds +"..G.MILESTONE_CROP_FORTUNE.." fortune for that crop in the garden and +"..G.MILESTONE_FORTUNE.." Farming Fortune everywhere.",
		lines={"Milestone tiers: "..fmt(num(g.milestoneTiers,0)).."   ·   +"..fmt(num(g.milestoneTiers,0)*G.MILESTONE_FORTUNE).." Farming Fortune"}})
	for _,c in ipairs(G.Crops) do
		local m=tbl(ms[c.id])
		local n=num(m.count,0)
		local tier=G.milestoneTier(c.id,n)
		local nextAt=G.milestoneThreshold(c.id,tier+1)
		local prev=G.milestoneThreshold(c.id,tier) or 0
		local labels={}
		for t=1,#G.MILESTONES do labels[t]=short(G.milestoneThreshold(c.id,t)) end
		local reward=nextAt and G.milestoneReward(c.id,tier+1)
		card({name="Milestone"..c.id,item=c.id,title=escape(itemName(c.id)),titleColor=rgb(c.tint),
			subtitle="Tier "..tier.."/"..#G.MILESTONES.."   ·   "..fmt(n).." harvested   ·   +"..(tier*G.MILESTONE_CROP_FORTUNE).." crop fortune",
			pips={total=#G.MILESTONES,filled=tier,color=rgb(c.tint),labels=if compactAtlas then nil else labels},
			bar={fraction=if nextAt then math.clamp((n-prev)/math.max(1,nextAt-prev),0,1) else 1,color=rgb(c.tint),caption=if nextAt then fmt(n).." / "..fmt(nextAt) else "All milestones reached"},
			lines={if reward then "Next tier: +"..fmt(reward.coins).." coins, +"..reward.gxp.." garden XP" else nil}})
	end
end
function GD.drawShop(g)
	local G=Data.Garden
	local level=num(g.level,1)
	local skins=tbl(g.skins)
	local ownedEntries=tbl(g.owned) -- server: unique entries owned directly or through an upgrade (a Greenward Hoe owns the Sproutwood)
	card({name="GardenShopIntro",motif="Ledger",title="Verdant Garden shop",titleColor=gold,subtitle=paint("✦ "..fmt(count("items",G.MARK)).." Verdant Marks","5FBF77").."   ·   "..fmt(count("items",G.DUST)).." Bloom Dust   ·   "..fmt(num(state.coins,0)).." coins",
		detail="Visitors pay in Verdant Marks; the composter leaves Bloom Dust. Hoes upgrade in place: buying the next one consumes the last."})
	for _,e in ipairs(G.Shop) do
		local reason
		if level<e.level then reason="Reach garden level "..e.level.."." end
		if e.kind=="skin" then
			local s=G.SkinById[e.skin]
			local owned=skins[e.skin]==true
			local applied=g.skin==e.skin
			if not owned and not reason and not GD.afford(e.cost) then reason="You need "..GD.costText(e.cost).."." end
			card({name="Shop"..e.id,motif="Workshop",accent=rgb(s.frame),title=escape(s.name).." plot skin",titleColor=rgb(lighten(s.frame,.35)),
				subtitle=if owned then (if applied then paint("APPLIED","9EE7D2") else paint("OWNED","9EE7D2")) else "Garden level "..e.level,
				lines={if owned then nil else "Cost: "..GD.costText(e.cost,true)},
				actions={if owned then {caption="Apply",primary=not applied,disabled=applied,reason="Already applied.",name="Apply"..e.skin,fn=function() send("gardenSkin",e.skin) end}
					else {caption="Buy",primary=reason==nil,disabled=reason~=nil,reason=reason,name="Buy"..e.id,fn=function() send("gardenBuy",e.id) end}}})
		else
			local def=itemDef(e.item)
			local owned=e.unique and (ownedEntries[e.id]==true or count("items",e.item)>0)
			if owned then reason=if count("items",e.item)>0 then "You already own one." else "Already owned through an upgrade." end
			if not reason and e.upgrade and count("items",e.upgrade)<1 then reason="Upgrades your "..itemName(e.upgrade)..": buy that first." end
			if not reason and not GD.afford(e.cost) then reason="You need "..GD.costText(e.cost).."." end
			card({name="Shop"..e.id,item=e.item,title=(if e.amount>1 then e.amount.."× " else "")..escape(itemName(e.item)),titleColor=rgb(itemHex(e.item)),
				subtitle=(def and escape(def.rarity or "Common") or "").."   ·   garden level "..e.level..(if owned then "   ·   "..paint("OWNED","9EE7D2") else ""),
				detail=def and escape(def.description or "") or nil,lines={"Cost: "..GD.costText(e.cost,true)..(if e.upgrade then "   ·   consumes your "..escape(itemName(e.upgrade)) else "")},
				actions={{caption="Buy",primary=reason==nil,disabled=reason~=nil,reason=reason,name="Buy"..e.id,fn=function() send("gardenBuy",e.id) end}}})
		end
	end
	-- Owned skins without a shop entry (the free default) can be re-applied.
	if g.skin~="Loam" then
		card({name="ShopLoam",motif="Workshop",title="Tilled Loam plot skin",titleColor=muted,subtitle=paint("OWNED","9EE7D2"),
			actions={{caption="Apply",name="ApplyLoam",fn=function() send("gardenSkin","Loam") end}}})
	end
end
function GD.draw()
	table.clear(GD.timers)
	GD.drawnAt=os.clock()
	heading("VERDANT GARDEN    /    PLOTS · VISITORS · COMPOSTER")
	if not GD.ready() then dataMissing() return end
	local g=GD.state()
	if next(g)==nil then syncing("garden") return end
	GD.summary(g)
	sectionBar(GD.VIEWS,GD.view,function(name)
		GD.view=name
		GD.selected=nil
		scroll.CanvasPosition=Vector2.zero
		render()
	end,{small=true,prefix="Garden"})
	if GD.view=="Visitors" then GD.drawVisitors(g)
	elseif GD.view=="Composter" then GD.drawComposter(g)
	elseif GD.view=="Milestones" then GD.drawMilestones(g)
	elseif GD.view=="Shop" then GD.drawShop(g)
	else GD.drawPlots(g) end
end
Pages.drawGarden=GD.draw
task.spawn(function()
	while task.wait(1) do
		if #GD.timers>0 and atlas.Visible and current=="Workshop" and sectionOf and sectionOf.Workshop=="Garden" then
			local elapsed=os.clock()-GD.drawnAt
			for _,t in ipairs(GD.timers) do pcall(function() t.label.Text=t.fn(elapsed) end) end
		end
	end
end)
end

------------------------------------------------------------------------------
-- Prayer & Thieving (Prayer & Thieving team). Pages: Hero › Prayer (point
-- gauge and drain, the prayer book grid with unlock levels and active
-- toggles, a detail card that toggles and sets HUD favourites, altars, remains
-- offerings and draughts) and Hunt › Thieving (targets by kind with success
-- chance, pace, loot tables, cooldowns and stun state; gloves).
-- Server state: snapshot.prayer = {points, max, active, quick, drain,
-- secondsLeft, offered, altar, altarUntil, riteIn}; snapshot.thieving =
-- {thefts, gloves, gloveBonus, deftness, chances, cooldowns, stunIn}.
-- Verbs: prayer "<id>", prayerOff, prayerQuick "<slot>:<id>", offerRemains
-- "<remains>" (while an altar visit is open), consume "<draught>". The combat
-- HUD's quick prayer bar relays taps through IsleActionLocal("prayer", id).
------------------------------------------------------------------------------
do
local PT={sel=nil}
Pages.PT=PT
function PT.ready() return Data and type(Data.Prayer)=="table" and type(Data.Thieving)=="table" end
function PT.level(skill) local info=skillsOf(state)[skill] return info and info.level or 1 end
function PT.guide(specs,label)
	if Pages.AH and Pages.AH.guide then Pages.AH.guide(specs,label) end
end
function PT.groupText(def)
	local names={}
	for _,g in ipairs(tbl(def.groups)) do table.insert(names,tbl(Data.Prayer.Groups)[g] or g) end
	return #names>0 and table.concat(names,", ") or "Stacks with every prayer"
end
function PT.drawPrayer()
	if not PT.ready() then dataMissing() return end
	local PR=Data.Prayer
	local s=tbl(state.prayer)
	local level=PT.level("Prayer")
	local max=num(s.max,PR.maxPoints(level))
	local points=math.clamp(num(s.points,max),0,math.max(1,max))
	local active={}
	for _,id in ipairs(tbl(s.active)) do if type(id)=="string" and PR.PrayerById[id] then active[id]=true end end
	local stats=tbl(dget("stats"))
	local devotion=num(stats.devotion,0)
	local drain=num(s.drain,PR.drainPerSecond(active,devotion)*60)
	local left=num(s.secondsLeft,nil)
	local hex=skillHex("Prayer")
	local summaryActions={{caption="Altar",name="PrayerGuideAltar",fn=function() PT.guide({"anchor:Waypoint_Altar_QuayChapel"},"Altar") end}}
	if next(active)~=nil then table.insert(summaryActions,1,{caption="All off",name="PrayerAllOff",fn=function() send("prayerOff") end}) end
	card({name="PrayerSummary",icon=function(parent,size) return titleArt(parent,"Prayer",size,"Hero") end,accent=rgb(hex),
		title="Prayer book",titleColor=gold,subtitle="Prayer "..level.."   ·   "..fmt(math.floor(points)).." / "..fmt(max).." points   ·   ✧ Devotion "..fmt(devotion),
		badge=state.prayer and ("Lv "..level) or "SYNCING",badgeColor=rgb(lighten(hex,.2)),
		detail="Active prayers drain points every few seconds; Devotion slows the drain. Pray at an altar or drink a draught to refill. Protection prayers cut that style's damage by "..
			math.floor(PR.PROTECT*100).."% ("..math.floor(PR.PROTECT_WORLD_BOSS*100).."% against world bosses).",
		bar={fraction=points/math.max(1,max),color=rgb(hex),caption=fmt(math.floor(points)).." / "..fmt(max).." points"..(drain>0 and ("   ·   -"..fmt(drain).." / min"..(left and ("   ·   "..clock(left).." left") or "")) or "   ·   no drain")},
		actions=summaryActions})
	heading("PRAYER BOOK    /    "..#PR.Prayers.." PRAYERS")
	local width=contentWidth()
	local columns=width>=690 and 7 or (width>=520 and 6 or (width>=400 and 5 or 4))
	local cellHeight=compactAtlas and 70 or 80
	local grid=gridHolder(UDim2.new(1/columns,-6,0,cellHeight),6)
	if not PT.sel or not PR.PrayerById[PT.sel] then
		PT.sel=PR.Prayers[1].id
		for _,def in ipairs(PR.Prayers) do if active[def.id] then PT.sel=def.id break end end
	end
	for i,def in ipairs(PR.Prayers) do
		local open=level>=def.level
		local on=active[def.id]==true
		local b=tile(grid,"Prayer"..def.id,i,function() PT.sel=def.id;render() end)
		local selected=PT.sel==def.id
		make("UIStroke",b,{Color=on and mint or (selected and gold or rgb(def.color)),Transparency=(on or selected) and 0 or .55,Thickness=(on or selected) and 2 or 1})
		if on then b.BackgroundColor3=rgb("1E4A44") end
		local glyph=label(b,def.glyph,0,compactAtlas and 4 or 6,full,compactAtlas and 26 or 30,UI.heavy,compactAtlas and 20 or 24,open and rgb(def.color) or muted)
		glyph.TextXAlignment=Enum.TextXAlignment.Center
		glyph.TextTransparency=open and 0 or .45
		local name=label(b,def.name,4,compactAtlas and 30 or 36,UDim.new(1,-8),compactAtlas and 18 or 20,bold,compactAtlas and 10 or 11,open and ivory or muted)
		name.TextXAlignment=Enum.TextXAlignment.Center
		name.TextScaled=true
		local foot=label(b,open and (on and "ON" or ("-"..def.drain.."/min")) or ("Lv "..def.level),4,compactAtlas and 49 or 57,UDim.new(1,-8),16,UI.heavy,compactAtlas and 10 or 11,on and mint or (open and muted or ember))
		foot.TextXAlignment=Enum.TextXAlignment.Center
	end
	local def=PR.PrayerById[PT.sel]
	local open=level>=def.level
	local on=active[def.id]==true
	local quick=tbl(s.quick)
	local hud={}
	for _,id in ipairs({PR.ProtectFor.melee,PR.ProtectFor.ranged,PR.ProtectFor.magic,quick[1],quick[2]}) do
		local d=type(id)=="string" and PR.PrayerById[id]
		if d then table.insert(hud,escape(d.name)) end
	end
	card({name="PrayerDetail",icon=function(parent,size) return itemGlyph(parent,{name=def.name,color=def.color},size,not open) end,iconSize=compactAtlas and 36 or 44,
		title=escape(def.name),titleColor=open and rgb(lighten(def.color,.3)) or muted,
		subtitle="Prayer "..def.level.."   ·   drains "..def.drain.." / min   ·   "..escape(PT.groupText(def)),
		badge=on and "ACTIVE" or (open and "READY" or ("Lv "..def.level)),badgeColor=on and mint or (open and ivory or ember),
		detail=escape(def.text),
		lines={"HUD quick bar: "..table.concat(hud,"  ·  ")},
		actions={{caption=on and "Stop" or "Pray",primary=not on,name="PrayerToggle",disabled=not open,reason=def.name.." requires Prayer "..def.level..".",
			fn=function() send("prayer",def.id) end},
			{caption="Quick 1",name="PrayerQuick1",fn=function() send("prayerQuick","1:"..def.id) end},
			{caption="Quick 2",name="PrayerQuick2",fn=function() send("prayerQuick","2:"..def.id) end}}})
	heading("ALTARS    /    OFFERINGS")
	local now=os.time()
	local window=type(s.altar)=="string" and num(s.altarUntil,0)>=now and s.altar or nil
	for _,altar in ipairs(PR.Altars) do
		local locked=type(altar.region)=="string" and player:GetAttribute(altar.region.."Unlocked")==false
		card({name="Altar"..altar.id,motif="Hero",title=escape(altar.name),titleColor=rgb(lighten(altar.color,.2)),
			subtitle="x"..altar.mult.." Prayer XP   ·   "..escape((Pages.AH and Pages.AH.regionName and Pages.AH.regionName(altar.region)) or altar.region),
			badge=window==altar.id and "OFFERING" or nil,badgeColor=mint,
			detail=escape(altar.text),
			lines={locked and paint("Unlock the region to reach this altar.","EF7D67") or nil},
			actions={{caption="Guide",name="GuideAltar"..altar.id,fn=function() PT.guide({"anchor:Waypoint_Altar_"..altar.id,"region:"..altar.region},altar.name) end}}})
	end
	local altarDef=window and PR.AltarById[window]
	local offered=tbl(s.offered)
	local riteIn=num(s.riteIn,0)
	for _,r in ipairs(PR.Remains) do
		local have=count("items",r.id)
		local each=r.xp*(altarDef and altarDef.mult or 1)
		card({name="Remains"..r.id,item=r.id,title=escape(r.name),titleColor=rgb(rarityHex(r.rarity)),
			subtitle="Held "..fmt(have).."   ·   "..fmt(each).." XP each"..(altarDef and (" at the "..escape(altarDef.name)) or ""),
			badge=fmt(num(offered[r.id],0)).." offered",badgeColor=muted,
			lines={if altarDef then nil else "Visit an altar, then offer from here for "..PR.ALTAR_SECONDS.."s. Each altar use offers up to "..PR.BATCH.."."},
			actions={{caption="Offer",name="Offer"..r.id,primary=altarDef~=nil and have>0,disabled=altarDef==nil or have<1 or riteIn>0,
				reason=if altarDef==nil then "Visit an altar first." elseif have<1 then "You have no "..r.name.."." else "The rite is still underway.",
				fn=function() send("offerRemains",r.id) end}}})
	end
	heading("DRAUGHTS")
	for _,id in ipairs({"DevotionDraught","ChoirTonic"}) do
		local d=itemDef(id)
		if d then
			local have=count("items",id)
			local restore=PR.restore(0,max,d)
			card({name="Draught"..id,item=id,title=escape(d.name),titleColor=rgb(rarityHex(d.rarity)),
				subtitle="Held "..fmt(have).."   ·   restores "..fmt(restore).." points now",detail=escape(d.description),
				actions={{caption="Drink",name="Drink"..id,disabled=have<1 or points>=max,reason=have<1 and ("Brew "..d.name.." at a Cauldron.") or "Your prayer points are full.",
					fn=function() send("consume",id) end}}})
		end
	end
end
function PT.drawThieving()
	if not PT.ready() then dataMissing() return end
	local TH=Data.Thieving
	local t=tbl(state.thieving)
	local thefts,chances,cooldowns=tbl(t.thefts),tbl(t.chances),tbl(t.cooldowns)
	local level=PT.level("Thieving")
	local stats=tbl(dget("stats"))
	local gloveId,gloveBonus=TH.gloves(tbl(state.items))
	if type(t.gloves)=="string" then gloveId,gloveBonus=t.gloves,num(t.gloveBonus,gloveBonus) end
	local deft=num(t.deftness,num(stats.deftness,0))
	local stun=num(t.stunIn,0)
	local total=0
	for _,target in ipairs(TH.Targets) do total+=num(thefts[target.id],0) end
	local hex=skillHex("Thieving")
	card({name="ThievingSummary",icon=function(parent,size) return titleArt(parent,"Thieving",size,"Hunt") end,accent=rgb(hex),
		title="Nightglove's ledger",titleColor=gold,subtitle="Thieving "..level.."   ·   "..fmt(total).." thefts   ·   ✋ Deftness "..fmt(deft),
		badge=stun>0 and ("STUNNED "..stun.."s") or ("Lv "..level),badgeColor=stun>0 and ember or rgb(lighten(hex,.3)),
		detail="Steal from stalls, pick pockets and crack strongboxes. Success rises with level, gloves and Deftness; a failure stuns you in place and hurts. Each target needs a moment to restock after a success.",
		lines={gloveId and ("Gloves: "..escape(itemName(gloveId)).." (+"..chance(gloveBonus).." success)") or "No thieving gloves: craft Lightfinger Gloves at a Workbench."}})
	for _,kindId in ipairs(TH.KindOrder) do
		local kind=TH.Kinds[kindId]
		heading(string.upper(kind.name).."S    /    "..string.upper(kind.verb))
		for _,target in ipairs(TH.Targets) do
			if target.kind==kindId then
				local open=level>=target.level
				local c=num(chances[target.id],TH.chance(target,level,gloveBonus,deft))
				local loot={fmt(target.coins[1]).."-"..fmt(target.coins[2]).." coins"}
				for _,drop in ipairs(target.drops) do
					table.insert(loot,escape(itemName(drop.item))..(drop.max>1 and (" x"..drop.min.."-"..drop.max) or "").." ("..chance(drop.chance)..")")
				end
				local wait=num(cooldowns[target.id],0)
				local locked=type(target.region)=="string" and player:GetAttribute(target.region.."Unlocked")==false
				card({name="Thieving"..target.id,icon=function(parent,size) return itemGlyph(parent,{name=target.name,color=target.color},size,not open) end,iconSize=compactAtlas and 36 or 44,
					title=escape(target.name),titleColor=open and rgb(lighten(target.color,.3)) or muted,
					subtitle="Thieving "..target.level.."   ·   "..escape((Pages.AH and Pages.AH.regionName and Pages.AH.regionName(target.region)) or target.region).."   ·   +"..fmt(target.xp).." XP",
					badge=open and (fmt(num(thefts[target.id],0)).." thefts") or ("Lv "..target.level),badgeColor=open and ivory or ember,
					lines={
						open and ("Success "..paint(chance(c),"7FE3CC").."   ·   restocks "..target.respawn.."s   ·   caught: "..target.stun.."s stun, -"..target.damage.." health") or nil,
						"Loot: "..table.concat(loot,"  ·  "),
						open and ("Pace: about "..short(TH.xpPerHour(target,c)).." XP and "..short(TH.coinsPerHour(target,c)).." coins an hour") or nil,
						wait>0 and paint("The "..escape(target.name).." is "..kind.wait.." ("..wait.."s).","F3C66E") or nil,
						locked and paint("Unlock the region to reach this target.","EF7D67") or nil,
					},
					actions={{caption="Guide",name="GuideThieving"..target.id,fn=function() PT.guide({"anchor:Waypoint_Thieving_"..target.id,"region:"..target.region},target.name) end}}})
			end
		end
	end
	heading("GLOVES")
	for _,id in ipairs(TH.GloveOrder) do
		local d=itemDef(id)
		if d then
			card({name="Gloves"..id,item=id,title=escape(d.name),titleColor=rgb(rarityHex(d.rarity)),
				subtitle="+"..chance(d.thievingBonus).." success   ·   "..(count("items",id)>0 and "owned" or "not owned"),detail=escape(d.description)})
		end
	end
end
Pages.drawPrayer,Pages.drawThieving=PT.drawPrayer,PT.drawThieving
end

------------------------------------------------------------------------------
-- Treasure Trails (Treasure Trails team). Page: Satchel › Trails — one card per
-- tier (scroll / active step text, hint, step actions, caskets), the sliding
-- puzzle box, the clue log grid (counts per tier, uniques obtained) and trail
-- extras (emotes learned, waystone leaves, emote scrolls, banners).
-- Server state: snapshot.trails = {active={[tier]={step,kind,style,text,hint,
-- guide,gesture,wear,need,have,board,moves}}, log, uniques, emotes, banner, spade}.
-- Verbs: trailBegin/trailAbandon/trailOpen "<tier>", trailDig/trailSearch
-- "<tier>", trailEmote "<gesture>", trailSlide "<tier>:<UDLR...>", trailCheck,
-- trailTeleport/trailLearn/trailBanner "<item>". Hints never carry answers.
------------------------------------------------------------------------------
do
local TT={puzzle={}}
Pages.TT=TT
function TT.ready() return Data and type(Data.Trails)=="table" end
function TT.guide(specs,label)
	if Pages.AH and Pages.AH.guide then Pages.AH.guide(specs,label) end
end
function TT.gesture(name)
	local api=ReplicatedStorage:FindFirstChild("IsleGestureLocal")
	if api and api.Fire then pcall(function() api:Fire(name) end) end
end
-- Local puzzle buffer: {server=board the buffer starts from, board, moves}.
-- Buffered moves are sent when the box is solved, at 40 moves, after
-- TT.IDLE_SECONDS without a slide, when the atlas closes and when the page
-- or tab changes (TT.flush), so a closed page never loses moves.
TT.IDLE_SECONDS=2
TT.token=0
function TT.flush()
	for tier,buf in pairs(TT.puzzle) do
		if type(buf.moves)=="string" and #buf.moves>0 then
			-- send() answers nil only while another request is in flight: keep the
			-- moves and try again after the idle delay.
			if send("trailSlide",tier..":"..buf.moves)~=nil then TT.puzzle[tier]=nil -- the reply's board is the truth from here
			else task.delay(TT.IDLE_SECONDS,TT.flush) end
		else
			TT.puzzle[tier]=nil
		end
	end
end
atlas:GetPropertyChangedSignal("Visible"):Connect(function()
	if not atlas.Visible then TT.flush() end
end)
function TT.slide(tier,row,index)
	local TR=Data.Trails
	local buf=TT.puzzle[tier]
	if not buf or buf.server~=row.board then buf={server=row.board,board=row.board,moves=""} TT.puzzle[tier]=buf end
	local gap=string.find(buf.board,"0",1,true)
	if not gap then return end
	local gx,gy=(gap-1)%3,(gap-1)//3
	local tx,ty=(index-1)%3,(index-1)//3
	local dir=if tx==gx and ty==gy-1 then "U" elseif tx==gx and ty==gy+1 then "D" elseif ty==gy and tx==gx-1 then "L" elseif ty==gy and tx==gx+1 then "R" else nil
	if not dir then notify("Only a tile beside the gap can slide.") return end
	local nextBoard=TR.slide(buf.board,dir)
	if not nextBoard then return end
	buf.board,buf.moves=nextBoard,buf.moves..dir
	TT.token+=1
	if nextBoard==TR.SOLVED or #buf.moves>=40 then
		TT.flush()
	else
		local token=TT.token
		task.delay(TT.IDLE_SECONDS,function() if TT.token==token then TT.flush() end end)
	end
	render()
end
function TT.board(tier,row)
	local buf=TT.puzzle[tier]
	if buf and buf.server==row.board and buf.board then return buf.board,buf.moves end
	return row.board,""
end
function TT.drawPuzzle(tier,row,body,nextOrder)
	local board,pending=TT.board(tier,row)
	if type(board)~="string" or #board~=9 then return end
	local size=compactAtlas and 46 or 58
	local holder=make("Frame",body,{Name="TrailPuzzle"..tier,BackgroundTransparency=1,Size=UDim2.fromOffset(size*3+12,size*3+12),LayoutOrder=nextOrder()})
	make("UIGridLayout",holder,{CellSize=UDim2.fromOffset(size,size),CellPadding=UDim2.fromOffset(6,6),FillDirectionMaxCells=3,SortOrder=Enum.SortOrder.LayoutOrder})
	for i=1,9 do
		local c=board:sub(i,i)
		local b=tile(holder,"TrailTile"..tier..i,i,function() TT.slide(tier,row,i) end)
		if c=="0" then
			b.BackgroundTransparency=.8
		else
			local right=tonumber(c)==i
			make("UIStroke",b,{Color=right and mint or gold,Transparency=.2,Thickness=right and 2 or 1})
			local t=label(b,c,0,0,full,size,UI.heavy,compactAtlas and 20 or 24,right and mint or ivory)
			t.Size=UDim2.fromScale(1,1)
			t.TextXAlignment=Enum.TextXAlignment.Center
		end
	end
	para(body,"Moves made: "..fmt(num(row.moves,0)+#pending)..(#pending>0 and ("   ·   "..#pending.." not yet sent") or ""),nextOrder(),muted,12)
end
function TT.drawTier(tier,t)
	local TR=Data.Trails
	local def=TR.Tiers[tier]
	local active=tbl(tbl(t.active)[tier])
	local scrolls,caskets=count("items",def.scroll),count("items",def.casket)
	local log=tbl(tbl(t.log)[tier])
	local actions={}
	local lines={}
	local o={name="Trail"..tier,item=def.scroll,accent=rgb(def.color),title=escape(def.adj.." Trail   ·   "..tier),titleColor=rgb(def.color),
		subtitle=fmt(num(log.completed,0)).." completed   ·   "..fmt(num(log.opened,0)).." caskets opened",lines=lines,actions=actions}
	if active.kind then
		o.badge="STEP "..num(active.step,1)
		o.badgeColor=gold
		o.detail=escape(tostring(active.text or ""))
		table.insert(lines,paint("Hint: ","F3C66E")..escape(tostring(active.hint or "")))
		local kind=active.kind
		if kind=="dig" then
			table.insert(actions,{caption="Dig",name="TrailDig"..tier,primary=true,disabled=t.spade~=true,reason="Forge a Wayfinder's Spade first.",fn=function() send("trailDig",tier) end})
		elseif kind=="riddle" then
			table.insert(actions,{caption="Search",name="TrailSearch"..tier,primary=true,fn=function() send("trailSearch",tier) end})
		elseif kind=="emote" then
			local wear={}
			for _,id in ipairs(tbl(active.wear)) do
				local on=false
				for _,eq in pairs(tbl(dget("equipment"))) do if eq==id then on=true end end
				table.insert(wear,(on and check or cross).." "..escape(itemName(id)))
			end
			if #wear>0 then table.insert(lines,"Wear: "..table.concat(wear,"  ")) end
			local g=tostring(active.gesture)
			table.insert(actions,{caption="Perform",name="TrailEmote"..tier,primary=true,fn=function() TT.gesture(g) send("trailEmote",g) end})
		elseif kind=="skill" then
			local need,have=num(active.need,1),num(active.have,0)
			o.bar={fraction=math.clamp(have/math.max(1,need),0,1),color=rgb(def.color),caption=fmt(have).." / "..fmt(need)}
			table.insert(actions,{caption="Check",name="TrailCheck"..tier,fn=function() send("trailCheck") end})
		elseif kind=="puzzle" then
			o.after=function(body,nextOrder) TT.drawPuzzle(tier,active,body,nextOrder) end
		end
		local specs=tbl(active.guide)
		if #specs>0 then table.insert(actions,{caption="Guide",name="TrailGuide"..tier,fn=function() TT.guide(specs,tier.." trail") end}) end
		table.insert(actions,{caption="Abandon",name="TrailAbandon"..tier,fn=function() send("trailAbandon",tier) end})
	elseif scrolls>0 then
		o.badge="SCROLL"
		o.badgeColor=mint
		o.detail="You carry a "..escape(itemName(def.scroll))..". Read it to begin: "..def.steps[1].."-"..def.steps[2].." steps."
		table.insert(actions,{caption="Read",name="TrailBegin"..tier,primary=true,fn=function() send("trailBegin",tier) end})
	else
		o.badge="NONE"
		o.badgeColor=muted
		o.detail=tier=="Master" and "Master scrolls hide in Starlit (Elite) caskets and in the hoards of the mightiest foes." or
			("Found while fighting, gathering, fishing, thieving and hunting content of "..tier.." difficulty.")
	end
	if caskets>0 then
		table.insert(actions,1,{caption="Open",name="TrailOpen"..tier,primary=not active.kind,fn=function() send("trailOpen",tier) end})
		table.insert(lines,fmt(caskets).." "..escape(itemName(def.casket))..(caskets>1 and "s" or "").." waiting.")
	end
	card(o)
end
function TT.drawLog(t)
	local TR=Data.Trails
	local uniques=tbl(t.uniques)
	local total,found=0,0
	for _,tier in ipairs(TR.TierOrder) do for _,id in ipairs(TR.Uniques[tier]) do total+=1 if num(uniques[id],0)>0 then found+=1 end end end
	heading("CLUE LOG    /    "..found.." OF "..total.." UNIQUES")
	local width=contentWidth()
	local columns=width>=690 and 8 or (width>=520 and 7 or (width>=400 and 6 or 5))
	local cell=compactAtlas and 62 or 72
	for _,tier in ipairs(TR.TierOrder) do
		local def=TR.Tiers[tier]
		local log=tbl(tbl(t.log)[tier])
		local row=container()
		row.Name="TrailLog"..tier
		local caption=label(row,paint(tier,def.color).."   ·   "..fmt(num(log.completed,0)).." completed   ·   "..fmt(num(log.opened,0)).." opened",4,0,UDim.new(1,-8),20,UI.heavy,12,ivory)
		caption.RichText=true
		row.Size=UDim2.new(1,-7,0,22)
		row.AutomaticSize=Enum.AutomaticSize.None
		local grid=gridHolder(UDim2.new(1/columns,-6,0,cell),6)
		grid.Name="TrailLogGrid"..tier
		for i,id in ipairs(TR.Uniques[tier]) do
			local n=num(uniques[id],0)
			local b=tile(grid,"TrailUnique"..id,i,function() notify(itemName(id)..(n>0 and (" x"..n) or " — not yet found")) end)
			itemIcon(b,id,compactAtlas and 34 or 40,n<=0).Position=UDim2.new(.5,-(compactAtlas and 17 or 20),0,4)
			local foot=label(b,n>0 and ("x"..n) or "?",2,cell-18,UDim.new(1,-4),16,UI.heavy,11,n>0 and mint or muted)
			foot.TextXAlignment=Enum.TextXAlignment.Center
		end
	end
end
function TT.drawExtras(t)
	local TR=Data.Trails
	local items=tbl(state.items)
	heading("TRAIL KIT    /    EMOTES, LEAVES AND BANNERS")
	local known=tbl(t.emotes)
	for _,e in ipairs(TR.EmoteOrder) do
		local def=TR.Emotes[e]
		if table.find(known,e) then
			card({name="TrailEmoteKnown"..e,motif="Hero",title=escape(def.name),subtitle="Learned emote",
				actions={{caption="Perform",name="TrailPerform"..e,fn=function() TT.gesture(def.gesture) end}}})
		end
	end
	for id,n in pairs(items) do
		local d=type(id)=="string" and num(n,0)>0 and itemDef(id)
		if d and d.kind=="trail" then
			if d.category=="emote" then
				card({name="TrailItem"..id,item=id,title=escape(d.name),titleColor=rgb(rarityHex(d.rarity)),subtitle="Held "..fmt(n),detail=escape(d.description),
					actions={{caption="Learn",name="TrailLearn"..id,primary=true,fn=function() send("trailLearn",id) end}}})
			elseif d.category=="teleport" then
				card({name="TrailItem"..id,item=id,title=escape(d.name),titleColor=rgb(rarityHex(d.rarity)),subtitle="Held "..fmt(n),detail=escape(d.description),
					actions={{caption="Travel",name="TrailTeleport"..id,fn=function() send("trailTeleport",id) end}}})
			elseif d.category=="banner" then
				local raised=t.banner==id
				card({name="TrailItem"..id,item=id,title=escape(d.name),titleColor=rgb(rarityHex(d.rarity)),subtitle=raised and "Raised" or "Held",detail=escape(d.description),
					actions={{caption=raised and "Lower" or "Raise",name="TrailBanner"..id,fn=function() send("trailBanner",raised and "none" or id) end}}})
			end
		end
	end
end
function TT.draw()
	if not TT.ready() then dataMissing() return end
	local TR=Data.Trails
	local t=tbl(state.trails)
	local done=0
	for _,tier in ipairs(TR.TierOrder) do done+=num(tbl(tbl(t.log)[tier]).completed,0) end
	card({name="TrailsSummary",item=TR.SPADE,accent=gold,title="Treasure Trails",titleColor=gold,
		subtitle=fmt(done).." trails completed   ·   "..(t.spade==true and "spade packed" or "no spade"),
		badge=if state.trails then nil else "SYNCING",
		detail="Scrolls lead from riddle to map to dig site. Dig with a Wayfinder's Spade, search where riddles point, perform emotes at landmarks, finish trail tasks and crack puzzle boxes. Each step is checked by the guild, so the only way through is to walk it.",
		lines={if t.spade==true then nil else paint("Forge a Wayfinder's Spade (1 Alloy Ingot, 2 Timber) at a Forge before your first dig.","F3C66E")}})
	heading("TRAILS    /    ONE SCROLL PER TIER")
	for _,tier in ipairs(TR.TierOrder) do TT.drawTier(tier,t) end
	TT.drawLog(t)
	TT.drawExtras(t)
end
Pages.drawTrails=TT.draw
end

------------------------------------------------------------------------------
-- Minigames (Minigames team). Page: Hunt › Minigames — views Lobbies (the
-- Skybreach Siege landings and the Tempest Haul gangway: live pad state from
-- workspace attribute MinigameLobbies, rules, your eligibility), Shop
-- (Commendation rewards: Lumenward outfit, XP lamps, titles), Caches (Squall
-- Cache rolls and the Haul uniques) and Log (games played / won / points).
-- In-game HUD "MinigameHud": the right column under the minimap (the
-- Observatory party HUD's slot: one cannot be in both) reading player
-- attributes MinigameGame / MinigameHud ("k=v;..."): Siege wave, portal
-- shields, Keeper HP, your points; Haul energy/essence, hull, fires, masts,
-- carried fish, your points. Toasts: MinigameNotice / MinigameNoticeCount.
-- Verbs: mgBuy "<shop id>", mgRoll "1"|"all", mgTitle "<id>|none".
------------------------------------------------------------------------------
do
local MGU={view="Lobbies",views={"Lobbies","Shop","Caches","Log"}}
Pages.MGU=MGU
local function rules() return Data and type(Data.Minigames)=="table" and Data.Minigames or nil end
-- "k=v;k=v" -> table (strings).
function MGU.parse(text)
	local out={}
	if type(text)~="string" then return out end
	for pair in text:gmatch("[^;]+") do
		local k,v=pair:match("^([%w_]+)=(.*)$")
		if k then out[k]=v end
	end
	return out
end
function MGU.lobbies()
	local ok,value=pcall(function() return workspace:GetAttribute("MinigameLobbies") end)
	local out={}
	for id,v in pairs(MGU.parse(ok and value or nil)) do
		local st,n,secs=v:match("^(%a+),(%d+),(%d+)$")
		if st then out[id]={state=st,count=tonumber(n),seconds=tonumber(secs)} end
	end
	return out
end
local function ledger() return type(state.minigames)=="table" and state.minigames or nil end
local function lobbyLine(l,label,ok,why)
	local s=l or {state="idle",count=0,seconds=0}
	local status=s.state=="running" and paint("MATCH IN PROGRESS","EF7D67") or s.state=="counting" and paint("LAUNCHING IN "..num(s.seconds,0).."s","F3C66E")
		or paint(num(s.count,0).." ON THE PAD","7FE3CC")
	return (ok and check or cross).." "..escape(label).."   ·   "..status..(ok and "" or "   "..paint(escape(why or ""),"E8806A"))
end
function MGU.drawLobbies(MG,m)
	local skills=skillsOf(state)
	local combat,fishing=skills.Combat and skills.Combat.level or 1,skills.Fishing and skills.Fishing.level or 1
	local lob=MGU.lobbies()
	card({name="MinigamesSummary",motif="Hunt",accent=gold,title=escape(MG.ISLAND),titleColor=gold,
		subtitle=fmt(m and m.commendations or 0).." Commendations   ·   "..fmt(m and m.rolls or 0)..(num(m and m.rolls,0)==1 and " Squall Cache roll" or " Squall Cache rolls"),badge=if m then nil else "SYNCING",
		detail="Board the Skybreach ferry on the Guild Terrace (Combat "..MG.Siege.Tiers[1].combat.." or Fishing "..MG.Haul.FISHING_LEVEL.."). Stand on a lobby pad: the match launches when enough players wait through the countdown.",
		lines={paint("Points come only from what you do: strikes, repairs, catches, cooking, loading, dousing. Idle players are removed after "..MG.IDLE_SECONDS.."s and earn nothing. Disconnected? Rejoin within "..MG.REJOIN_SECONDS.."s to keep your points.","A9BDC1")}})
	local S,H=MG.Siege,MG.Haul
	local lines={}
	for _,t in ipairs(S.Tiers) do
		local ok=combat>=t.combat
		table.insert(lines,lobbyLine(lob["Siege"..t.id],t.name.." (Combat "..t.combat..", "..t.commendations.." Commendations)",ok,if ok then nil else "Combat "..t.combat))
	end
	card({name="MinigameSiege",motif="Hunt",accent=rgb(S.color),title=escape(S.name),titleColor=rgb(S.color),
		subtitle=S.MIN_PLAYERS.."-"..S.MAX_PLAYERS.." players   ·   defend the "..escape(S.keeper),detail=escape(S.rules),lines=lines})
	local fishOk=fishing>=H.FISHING_LEVEL
	card({name="MinigameHaul",motif="Hunt",accent=rgb(H.color),title=escape(H.name),titleColor=rgb(H.color),
		subtitle="1-"..H.MAX_PLAYERS.." players   ·   the "..escape(H.boss),detail=escape(H.rules),
		lines={lobbyLine(lob.Haul,"Haul gangway (Fishing "..H.FISHING_LEVEL..")",fishOk,if fishOk then nil else "Fishing "..H.FISHING_LEVEL),
			paint("Fishing, Cooking and Carpentry XP for every action. Solo hauls pay "..math.floor(H.SOLO_REWARD*100).."% of the cache rolls.","A9BDC1")}})
end
function MGU.drawShop(MG,m)
	heading("COMMENDATION SHOP    /    "..fmt(m.commendations).." BANKED")
	local skills=skillsOf(state)
	local unlocks={}
	for _,id in ipairs(type(m.unlocks)=="table" and m.unlocks or {}) do unlocks[id]=true end
	for _,e in ipairs(MG.Shop) do
		local afford=num(m.commendations,0)>=e.cost
		local o={name="MinigameShop"..e.id,accent=afford and mint or UI.line,badge=fmt(e.cost).." C",badgeColor=afford and gold or muted}
		local actions={}
		if e.kind=="armor" then
			local def=itemDef(e.item) or {}
			local style=MG.LumenwardStyle[e.item]
			local need=type(def.requires)=="table" and num(def.requires.Combat,0) or 0
			local met=(skills.Combat and skills.Combat.level or 1)>=need
			o.item=e.item
			o.title=paint(escape(def.name or e.item),itemHex(e.item))
			o.subtitle=(slotNames[def.slot] or "Armor").."   ·   owned "..fmt(count("items",e.item))
			o.lines={statText(def.stats),style and paint("Full Lumenward with this helm: ","A9BDC1")..statText(style.stats) or nil,
				not met and paint("Requires Combat "..need,"E8806A") or nil}
			table.insert(actions,{caption="Buy",primary=true,name="MinigameBuy"..e.id,disabled=not afford or not met,
				reason=not met and ("Requires Combat "..need..".") or ("Needs "..e.cost.." Commendations."),fn=function() send("mgBuy",e.id) end})
		elseif e.kind=="lamp" then
			local xp=num(tbl(m.lamps)[e.skill],0)
			o.motif="Hero"
			o.title="Lumen Lamp: "..escape(e.skill)
			o.subtitle="+"..fmt(xp).." "..escape(e.skill).." XP at your level"
			table.insert(actions,{caption="Buy",primary=true,name="MinigameBuy"..e.id,disabled=not afford,reason="Needs "..e.cost.." Commendations.",fn=function() send("mgBuy",e.id) end})
		else
			local owned=unlocks[e.id]==true
			o.motif="Journal"
			o.title="Title: "..escape(e.title)
			o.subtitle=owned and (m.title==e.id and "Wearing" or "Owned") or "Cosmetic title shown over your head"
			if owned then
				table.insert(actions,{caption=m.title==e.id and "Hide" or "Wear",name="MinigameWear"..e.id,fn=function() send("mgTitle",m.title==e.id and "none" or e.id) end})
			else
				table.insert(actions,{caption="Buy",primary=true,name="MinigameBuy"..e.id,disabled=not afford,reason="Needs "..e.cost.." Commendations.",fn=function() send("mgBuy",e.id) end})
			end
		end
		o.actions=actions
		card(o)
	end
end
function MGU.drawCaches(MG,m)
	local H=MG.Haul
	local rolls=num(m.rolls,0)
	card({name="MinigameCache",motif="Satchel",accent=rgb(H.color),title="Squall Caches",titleColor=rgb(H.color),badge=fmt(rolls).." ROLLS",
		subtitle="Coins, stormfish, timber, dust and storm-gifts",detail="Each Tempest Haul win with "..H.MIN_POINTS.."+ points banks a roll per "..H.ROLL_POINTS.." points (up to "..H.MAX_ROLLS.." per haul).",
		actions={{caption="Open 1",primary=true,name="MinigameRollOne",disabled=rolls<1,reason="No Squall Cache rolls banked.",fn=function() send("mgRoll","1") end},
			{caption="Open all",name="MinigameRollAll",disabled=rolls<1,reason="No Squall Cache rolls banked.",fn=function() send("mgRoll","all") end}}})
	heading("HAUL UNIQUES    /    RARE CACHE FINDS")
	for _,u in ipairs(H.Cache.uniques) do
		local have=count("items",u.item)+count("collection",u.item)
		card({name="MinigameUnique"..u.item,item=u.item,title=paint(escape(itemName(u.item)),itemHex(u.item)),subtitle="1 in "..math.floor(1/u.chance+.5).." per roll",
			badge=have>0 and "FOUND" or nil,badgeColor=mint})
	end
end
function MGU.drawLog(MG,m)
	heading("MINIGAME LOG    /    YOUR RECORD")
	for _,g in ipairs(MG.Order) do
		local def=MG[g]
		local l=tbl(tbl(m.log)[g])
		local played,won=num(l.played,0),num(l.won,0)
		card({name="MinigameLog"..g,motif="Journal",accent=rgb(def.color),title=escape(def.name),titleColor=rgb(def.color),
			subtitle=fmt(played).." played   ·   "..fmt(won).." won"..(played>0 and ("   ·   "..math.floor(won/played*100+.5).."%") or ""),
			lines={"Points earned: "..fmt(l.points).."   ·   best match: "..fmt(l.best),
				(g=="Siege" and "Commendations earned: " or "Cache rolls earned: ")..fmt(l.paid)}})
	end
end
function MGU.draw()
	local MG=rules()
	if not MG then syncing("minigames") return end
	sectionBar(MGU.views,MGU.view,function(name) MGU.view=name render() end,{small=true,prefix="MinigameView",maxPer=4})
	local m=ledger()
	if MGU.view=="Lobbies" then return MGU.drawLobbies(MG,m) end
	if not m then syncing("minigames") return end
	if MGU.view=="Shop" then MGU.drawShop(MG,m)
	elseif MGU.view=="Caches" then MGU.drawCaches(MG,m)
	else MGU.drawLog(MG,m) end
end
Pages.drawMinigames=MGU.draw

-- In-game HUD.
local hudFrame=make("TextButton",gui,{Name="MinigameHud",Text="",AutoButtonColor=false,BackgroundColor3=deep,BackgroundTransparency=.06,BorderSizePixel=0,
	AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-10,0,204),Size=UDim2.fromOffset(220,46),Visible=false,Selectable=false})
rounded(hudFrame,12,UI.brass)
local title=label(hudFrame,"",12,4,UDim.new(1,-24),16,UI.heavy,11,gold)
title.Name="Title"
local body=label(hudFrame,"",12,20,UDim.new(1,-24),18,bold,12,ivory)
body.Name="Lines"
body.RichText=true
body.TextWrapped=true
body.TextYAlignment=Enum.TextYAlignment.Top
body.TextTruncate=Enum.TextTruncate.None
hudFrame.Activated:Connect(function() if Pages.openTo then Pages.openTo("Hunt","Minigames") end end)
MGU.hud=hudFrame
local function pct(text)
	local a,b=tostring(text or ""):match("^(%d+)/(%d+)$")
	a,b=tonumber(a),tonumber(b)
	if not a or not b or b<=0 then return 0 end
	return math.clamp(a/b,0,1)
end
local function bar(fraction,width)
	local n=math.floor(fraction*width+.5)
	return string.rep("█",n)..string.rep("░",width-n)
end
-- Lines for the HUD (short = phone column).
function MGU.hudLines(h,short)
	local lines={}
	local points=num(tonumber(h.points),0)
	local min=num(tonumber(h.min),0)
	local mine=paint((short and "★ " or "Your points ")..fmt(points),points>=min and "7FE3CC" or "F3C66E")..(points<min and paint(" / "..min,"A9BDC1") or "")
	if h.game=="Siege" then
		local keeper=pct(h.keeper)
		table.insert(lines,(short and "♥ " or "Keeper ")..paint(short and (math.floor(keeper*100).."%") or (bar(keeper,10).." "..math.floor(keeper*100).."%"),keeper>.35 and "7FE3CC" or "EF7D67"))
		local open,sealed,shield={},0,0
		for entry in tostring(h.portals or ""):gmatch("[^,]+") do
			local id,hp,max,sh=entry:match("^(%a+):(%d+):(%d+):(%d)$")
			if id then
				if tonumber(hp)==0 then sealed+=1 elseif sh=="1" then shield+=1 else table.insert(open,id.." "..math.floor(tonumber(hp)/math.max(1,tonumber(max))*100).."%") end
			end
		end
		if short then
			table.insert(lines,"◇ "..#open.." open  ✓"..sealed)
		else
			table.insert(lines,"Rifts: "..(#open>0 and paint(escape(table.concat(open,", ")),"F3C66E") or paint("all shielded","A9BDC1"))..paint("   ⛨"..shield.." ✓"..sealed,"A9BDC1"))
			table.insert(lines,"Wave "..escape(h.wave or "0").."   ·   "..escape(h.creatures or "0").." creatures")
		end
	else
		local vulnerable=h.phase=="vulnerable"
		local value=num(tonumber(vulnerable and h.essence or h.energy),0)
		table.insert(lines,(vulnerable and (short and "⚓ " or "Essence ") or (short and "⚡ " or "Energy "))..paint(short and (value.."%") or (bar(value/100,10).." "..value.."%"),vulnerable and "EF7D67" or "5EC8D8"))
		local hull=num(tonumber(h.hull),0)
		local masts=0
		for v in tostring(h.masts or ""):gmatch("[^,]+") do if v=="0" then masts+=1 end end
		if short then
			table.insert(lines,"⛵ "..hull.."%  🔥"..escape(h.fires or "0"))
		else
			table.insert(lines,"Hull "..paint(hull.."%",hull>40 and "7FE3CC" or "EF7D67").."   ·   fires "..escape(h.fires or "0").."   ·   cracked masts "..masts)
			table.insert(lines,"Carrying "..escape(h.raw or "0").." raw, "..escape(h.cooked or "0").." cooked")
		end
	end
	table.insert(lines,mine..(short and "" or paint("   ·   "..clock(tonumber(h.time)).." left","A9BDC1")))
	return lines
end
function MGU.refreshHud()
	local game=player:GetAttribute("MinigameGame")
	local h=MGU.parse(player:GetAttribute("MinigameHud"))
	local MG=rules()
	hudFrame.Visible=MG~=nil and (game=="Siege" or game=="Haul") and h.game==game
	if not hudFrame.Visible then return end
	local view=gui.AbsoluteSize
	local height=(view and view.Y>0) and view.Y or 720
	local short=height<520
	local width=short and 100 or 214
	local lanes=UI.lay()
		local top=lanes.rightTop
	local pad=short and 6 or 12
	local lines=MGU.hudLines(h,short)
	local def=MG[game]
	title.Text=short and string.upper(game) or string.upper(def.name)..(h.tier and ("  ·  "..string.upper(h.tier)) or "")
	title.TextColor3=rgb(def.color)
	title.TextSize=11
	local titleHeight=short and 14 or 16
	local rowHeight=short and 14 or 18
	title.Position,title.Size=UDim2.fromOffset(pad,4),UDim2.new(1,-2*pad,0,titleHeight)
	body.Text=table.concat(lines,"\n")
	body.TextSize=short and 11 or 12
	body.Position=UDim2.fromOffset(pad,4+titleHeight)
	body.Size=UDim2.new(1,-2*pad,0,rowHeight*#lines)
	hudFrame.Position=UDim2.new(0,lanes.rightEdge,0,top)
	hudFrame.Size=UDim2.fromOffset(width,4+titleHeight+rowHeight*#lines+8)
end
for _,name in ipairs({"MinigameGame","MinigameHud","IsleSatchelOpen"}) do
	player:GetAttributeChangedSignal(name):Connect(function() MGU.refreshHud() end)
end
player:GetAttributeChangedSignal("MinigameNoticeCount"):Connect(function()
	local message=player:GetAttribute("MinigameNotice")
	if type(message)=="string" and message~="" then notify(message) end
end)
MGU.refreshHud()
end
-- End Minigames section.
------------------------------------------------------------------------------
-- Lairs (Bossing team). Page: Hunt › Bosses — views Lairs (the four lair
-- bosses: altar, fee, requirements, mechanics, kill count and personal best),
-- Uniques (each boss's drop table with rarity labels and the uniques you have
-- looted) and Log (recent kills, deaths). Server state: snapshot.lairs =
-- {kc, pb, pbParty, got, deaths, log, active}. Summon at the altars (prompt
-- lairEnter); there is no remote verb to enter from the page.
-- In-fight HUD "LairHud": the right column under the minimap (the Observatory
-- party / Minigame HUD slot; one cannot be in two at once) reading player
-- attributes LairBoss / LairHud ("k=v;..."). Toasts: LairNotice / LairNoticeCount.
------------------------------------------------------------------------------
do
local LRU={view="Lairs",views={"Lairs","Uniques","Log"}}
Pages.LRU=LRU
local function rules() return Data and type(Data.Lairs)=="table" and Data.Lairs or nil end
local function ledger() return type(state.lairs)=="table" and state.lairs or nil end
local STYLE_HEX={melee="FF8A7A",ranged="96E178",magic="8CAAFF"}
local STYLE_GLYPH={melee="⚔",ranged="➶",magic="✦"}
local WARD={melee="Ward of Fangs",ranged="Ward of Quills",magic="Ward of Glyphs"}
function LRU.parse(text)
	local out={}
	if type(text)~="string" then return out end
	for pair in text:gmatch("[^;]+") do
		local k,v=pair:match("^([%w_]+)=(.*)$")
		if k then out[k]=v end
	end
	return out
end
local function styleText(style) return paint((STYLE_GLYPH[style] or "").." "..string.upper(tostring(style or "?")),STYLE_HEX[style] or "F7EFDC") end
function LRU.drawLairs(LR,l)
	local skills=skillsOf(state)
	local combat=skills.Combat and skills.Combat.level or 1
	local total=0
	for _,n in pairs(tbl(l and l.kc)) do total+=num(n,0) end
	card({name="LairsSummary",motif="Hunt",accent=rgb("B48CFF"),title="Lair Bosses",titleColor=rgb("D8C4FF"),
		subtitle=fmt(total).." lair kills   ·   up to "..LR.MAX_PARTY.." crewmates per lair",badge=if l then nil else "SYNCING",
		detail="Summon a lair boss at its altar (entry fee in coins). The arena opens for "..LR.WARMUP.."s so crewmates from your co-op can join, then the boss rises. Stances switch on a beat: pray the matching Ward. Dodge telegraphs and glowing tiles; slay broods first and break sigils in order.",
		lines={paint("Fall and you wake at home with your items (the usual purse-coin loss applies). Disconnected? Rejoin within "..LR.REJOIN_SECONDS.."s to keep your place and share. Each member rolls their own loot.","A9BDC1")}})
	for _,id in ipairs(LR.Order) do
		local def=LR.Bosses[id]
		local kc=num(tbl(l and l.kc)[id],0)
		local pb=tbl(l and l.pb)[id]
		local ok=combat>=def.combat
		local stances={}
		for _,s in ipairs(def.stances) do table.insert(stances,styleText(s)) end
		local lines={}
		for _,m in ipairs(def.mechanics) do table.insert(lines,"•  "..escape(m)) end
		table.insert(lines,"Weak to "..styleText(def.weakness).."   ·   stances "..table.concat(stances," → ").."   ·   enrage "..LR.formatTime(def.enrage))
		table.insert(lines,(pb and ("Personal best "..paint(LR.formatTime(pb),"7FE3CC")..paint(num(tbl(l.pbParty)[id],1)>1 and (" ("..num(tbl(l.pbParty)[id],1).." players)") or " (solo)","A9BDC1")) or paint("No kills yet","A9BDC1"))
			.."   ·   deaths "..fmt(num(tbl(l and l.deaths)[id],0)))
		if not ok then table.insert(lines,paint("Requires Combat "..def.combat,"E8806A")) end
		card({name="Lair"..id,motif="Hunt",accent=rgb(def.color),item=LR.Uniques[id].weapon,title=paint(escape(def.name),def.color),
			subtitle="Lv "..def.level.."   ·   "..escape(def.lairName).."   ·   altar on "..escape(def.isle).."   ·   "..fmt(def.fee).." coins",
			badge="KC "..fmt(kc),badgeColor=kc>0 and gold or muted,detail=escape(def.blurb),lines=lines})
	end
end
function LRU.drawUniques(LR,l)
	local got=tbl(l and l.got)
	for _,id in ipairs(LR.Order) do
		local def=LR.Bosses[id]
		local u=LR.Uniques[id]
		local found=0
		for _,item in ipairs({u.weapon,u.accessory,u.pet}) do if num(got[item],0)>0 then found+=1 end end
		heading(string.upper(def.short).."    /    "..found.."/3 UNIQUES")
		for _,d in ipairs(LR.Loot[id]) do
			local t=LR.dropTier(d.chance)
			local unique=LR.isUnique(d.item)
			local have=num(got[d.item],0)
			local odds=if d.chance>=1 then "every kill" elseif d.chance>=0.05 then math.floor(d.chance*100+.5).."%" else "1 in "..fmt(math.floor(1/d.chance+.5))
			card({name="LairDrop"..id..d.item,item=d.item,title=paint(escape(itemName(d.item)),itemHex(d.item)),
				subtitle=paint(string.upper(t.id),t.color).."   ·   "..odds..(d.max>1 and ("   ·   "..d.min.."-"..d.max) or ""),
				badge=unique and (have>0 and ("×"..fmt(have)) or "NOT YET") or nil,badgeColor=have>0 and mint or muted,
				detail=unique and escape(tbl(itemDef(d.item)).description or "") or nil})
		end
	end
end
function LRU.drawLog(LR,l)
	heading("RECENT KILLS    /    NEWEST FIRST")
	local log=tbl(l.log)
	if #log==0 then card({name="LairLogEmpty",motif="Journal",title="No lair kills yet",titleColor=muted,detail="Your last "..LR.KEEP_LOG.." lair kills appear here."}) end
	for i,e in ipairs(log) do
		local def=type(e)=="table" and type(e.b)=="string" and LR.Bosses[e.b] or nil
		if def then
			card({name="LairLog"..i,motif="Hunt",accent=rgb(def.color),title=paint(escape(def.short),def.color),
				subtitle=LR.formatTime(e.s).."   ·   "..(num(e.n,1)>1 and (e.n.." players") or "solo"),
				lines={type(e.u)=="string" and (paint("Unique: ","A9BDC1")..paint(escape(itemName(e.u)),itemHex(e.u))) or nil}})
		end
	end
end
function LRU.draw()
	local LR=rules()
	if not LR then syncing("lairs") return end
	sectionBar(LRU.views,LRU.view,function(name) LRU.view=name render() end,{small=true,prefix="LairView",maxPer=3})
	local l=ledger()
	if LRU.view=="Lairs" then return LRU.drawLairs(LR,l) end
	if not l then syncing("lairs") return end
	if LRU.view=="Uniques" then LRU.drawUniques(LR,l) else LRU.drawLog(LR,l) end
end
Pages.drawBosses=LRU.draw

-- In-fight HUD.
local hudFrame=make("TextButton",gui,{Name="LairHud",Text="",AutoButtonColor=false,BackgroundColor3=deep,BackgroundTransparency=.06,BorderSizePixel=0,
	AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-10,0,204),Size=UDim2.fromOffset(220,46),Visible=false,Selectable=false})
rounded(hudFrame,12,UI.brass)
local title=label(hudFrame,"",12,4,UDim.new(1,-24),16,UI.heavy,11,gold)
title.Name="Title"
local body=label(hudFrame,"",12,20,UDim.new(1,-24),18,bold,12,ivory)
body.Name="Lines"
body.RichText=true
body.TextWrapped=true
body.TextYAlignment=Enum.TextYAlignment.Top
body.TextTruncate=Enum.TextTruncate.None
hudFrame.Activated:Connect(function() if Pages.openTo then Pages.openTo("Hunt","Bosses") end end)
LRU.hud=hudFrame
local function bar(fraction,width)
	local n=math.floor(math.clamp(fraction,0,1)*width+.5)
	return string.rep("█",n)..string.rep("░",width-n)
end
function LRU.hudLines(h,short)
	local lines={}
	if h.state=="warmup" then
		table.insert(lines,(short and "⏳ " or "Rises in ")..paint(num(tonumber(h.rise),0).."s","F3C66E"))
		table.insert(lines,(short and "👥 " or "Party ")..escape(h.party or "1").."/"..(rules() and rules().MAX_PARTY or 3))
		return lines
	end
	if h.state=="won" then
		table.insert(lines,paint(short and "SLAIN" or "Slain in "..clock(tonumber(h.t)),"7FE3CC"))
		table.insert(lines,(short and "↩ " or "Returning in ")..num(tonumber(h.exit),0).."s")
		return lines
	end
	local a,b=tostring(h.hp or ""):match("^(%d+)/(%d+)$")
	local frac=(tonumber(a) or 0)/math.max(1,tonumber(b) or 1)
	table.insert(lines,(short and "♥ " or "")..paint(short and (math.floor(frac*100).."%") or (bar(frac,10).." "..math.floor(frac*100).."%"),frac>.33 and "7FE3CC" or "EF7D67"))
	local style=h.style
	local stance=styleText(style)
	if h["next"] and h["in"] then stance..=paint((short and " →" or "  → ")..(STYLE_GLYPH[h["next"]] or "")..(short and "" or (" in "..h["in"])),"A9BDC1") end
	table.insert(lines,stance)
	if not short then
		table.insert(lines,paint("Pray: "..(WARD[style] or "—"),"A9BDC1").."   ·   weak "..styleText(h.weak))
		local timer=h.enr=="1" and paint("ENRAGED","EF7D67") or ("enrage "..clock(tonumber(h.enrage)))
		table.insert(lines,timer.."   ·   "..clock(tonumber(h.t)))
	end
	if h.seal and h.seal~="0" then table.insert(lines,paint(short and ("⛓ "..h.seal) or ("Sealed: break sigil "..h.seal),"F3C66E"))
	elseif h.ward=="1" then table.insert(lines,paint(short and "⛨ brood" or "Brood ward: slay the brood","F3C66E")) end
	return lines
end
function LRU.refreshHud()
	local boss=player:GetAttribute("LairBoss")
	local h=LRU.parse(player:GetAttribute("LairHud"))
	local LR=rules()
	local def=nil
	if LR and type(boss)=="string" and boss~="" then def=LR.Bosses[boss] end
	hudFrame.Visible=def~=nil and h.boss==boss
	if not hudFrame.Visible then return end
	local view=gui.AbsoluteSize
	local height=(view and view.Y>0) and view.Y or 720
	local short=height<520
	local width=short and 96 or 220
	local lanes=UI.lay()
		local top=lanes.rightTop
	local pad=short and 6 or 12
	local lines=LRU.hudLines(h,short)
	title.Text=short and string.upper(def.short) or (string.upper(def.short)..(h.pname and h.pname~="" and ("  ·  "..string.upper(h.pname)) or ""))
	title.TextColor3=rgb(def.color)
	title.TextSize=short and 10 or 11
	local titleHeight=short and 14 or 16
	local rowHeight=short and 14 or 18
	title.Position,title.Size=UDim2.fromOffset(pad,4),UDim2.new(1,-2*pad,0,titleHeight)
	body.Text=table.concat(lines,"\n")
	body.TextSize=short and 11 or 12
	body.Position=UDim2.fromOffset(pad,4+titleHeight)
	body.Size=UDim2.new(1,-2*pad,0,rowHeight*#lines)
	hudFrame.Position=UDim2.new(0,lanes.rightEdge,0,top)
	hudFrame.Size=UDim2.fromOffset(width,4+titleHeight+rowHeight*#lines+8)
end
for _,name in ipairs({"LairBoss","LairHud","IsleSatchelOpen"}) do
	player:GetAttributeChangedSignal(name):Connect(function() LRU.refreshHud() end)
end
player:GetAttributeChangedSignal("LairNoticeCount"):Connect(function()
	local message=player:GetAttribute("LairNotice")
	if type(message)=="string" and message~="" then notify(message) end
end)
LRU.refreshHud()
end
-- End Lairs section.
-- Commissions & Logs (Mining & Logs team). Journal › Commissions (daily slots,
-- progress, reset timer, milestones, Forgeheart shop), Journal › Collection Log
-- (tab filter, icon grid, counts, tab rewards, score/rank, titles) and
-- Journal › Museum (category filter, icon grid, donate, milestones).
-- Server state: snapshot.logs = {rev, commissions, log, museum} when it changed,
-- else {rev, resetIn, compact = true}; CLP.logs() keeps the last full copy
-- (fed from every accepted snapshot) and asks "logsSync" on a cache miss.
-- Verbs: commissionClaim "<slot>", commissionClaimAll, forgeBuy "<perk>",
-- logClaim "<tab>", logTitle "<tab>|Paragon|none", museumDonate "<item>", logsSync.
------------------------------------------------------------------------------
do
local CLP={tab=nil,cat="Weapons",pick=nil,cache=nil,asked=nil,askedAt=0}
Pages.CLP=CLP
function CLP.ready() return Data and type(Data.CommissionsLogs)=="table" end
-- Every accepted snapshot passes here: full logs replace the cache; a compact
-- one refreshes the reset timer of the matching cached revision.
function CLP.observe(data)
	local logs=type(data)=="table" and data.logs
	if type(logs)~="table" then return end
	if logs.compact then
		local cached=CLP.cache
		if cached and cached.rev==logs.rev and type(cached.commissions)=="table" then cached.commissions.resetIn=logs.resetIn end
	elseif type(logs.commissions)=="table" then
		CLP.cache=logs
	end
end
-- The logs to draw (nil = not synced). A compact snapshot whose revision is
-- not cached asks the server once (retry after 3 s) for the full copy.
function CLP.logs()
	local logs=state and state.logs
	if type(logs)~="table" then return nil end
	if not logs.compact then CLP.observe(state) return logs end
	local cached=CLP.cache
	if cached and cached.rev==logs.rev then return cached end
	if send and (CLP.asked~=logs.rev or os.clock()-CLP.askedAt>3) then
		CLP.asked,CLP.askedAt=logs.rev,os.clock()
		task.defer(function() send("logsSync",nil,true) end)
	end
	return cached -- an older copy while the fresh one is on its way
end
function CLP.clock(seconds)
	seconds=math.max(0,math.floor(num(seconds,0)))
	return string.format("%dh %02dm",seconds//3600,(seconds%3600)//60)
end
function CLP.grid(name,ids,cell,each)
	local width=contentWidth()
	local columns=width>=690 and 8 or (width>=520 and 7 or (width>=400 and 6 or 5))
	local grid=gridHolder(UDim2.new(1/columns,-6,0,cell),6)
	grid.Name=name
	for i,id in ipairs(ids) do each(grid,i,id) end
	return grid
end
function CLP.drawCommissions()
	if not CLP.ready() then dataMissing() return end
	local CL=Data.CommissionsLogs
	local logs=CLP.logs()
	local c=tbl(tbl(logs).commissions)
	local g=tbl(tbl(logs).log)
	local slots=tbl(c.slots)
	local ready=0
	for _,s in ipairs(slots) do if s.done and not s.claimed then ready+=1 end end
	card({name="CommissionsSummary",motif="Journal",accent=rgb(CL.DUST.color),title="Commissions",titleColor=gold,
		subtitle=paint(CL.DUST.symbol.." "..fmt(num(c.dust,0)).." "..CL.DUST.name,CL.DUST.color).."   ·   "..fmt(num(c.total,0)).." completed",
		badge=logs and ("RESETS "..CLP.clock(c.resetIn)) or "SYNCING",badgeColor=mint,
		detail="Four guild commissions a day, posted at the Commission Board in Brassfall Quarry. A new board is drawn at the UTC day change; finished commissions are claimed for you if you forget.",
		actions=ready>0 and {{caption="Claim all",name="CommissionClaimAll",primary=true,fn=function() send("commissionClaimAll") end}} or nil})
	heading("TODAY'S COMMISSIONS    /    "..#slots.." OF "..CL.SLOTS)
	for i,s in ipairs(slots) do
		local t=CL.TaskById[s.id]
		if t then
			local r=tbl(s.reward)
			local amount=t.amount
			local progress=math.min(num(s.progress,0),amount)
			local verb=t.kind=="kill" and "Defeat" or (t.kind=="catch" and "Catch" or (t.kind=="craft" and "Craft" or "Harvest"))
			local target=t.kind=="kill" and (Data.Monsters[t.target] and Data.Monsters[t.target].name or t.target)
				or (t.kind=="catch" and Data.Hunter and Data.Hunter.CreatureById[t.target] and Data.Hunter.CreatureById[t.target].name) or itemName(t.target)
			local actions={}
			if s.claimed then
			elseif s.done then table.insert(actions,{caption="Claim",name="CommissionClaim"..i,primary=true,fn=function() send("commissionClaim",tostring(i)) end})
			end
			card({name="Commission"..i,item=(t.kind=="gather" and t.target) or nil,motif=t.kind~="gather" and "Hunt" or nil,accent=rgb(CL.DUST.color),
				title=escape(t.name),titleColor=ivory,subtitle=escape(t.group or t.skill).."   ·   "..verb.." "..amount.." "..escape(target),
				badge=s.claimed and "CLAIMED" or (s.done and "READY" or "ACTIVE"),badgeColor=s.claimed and muted or (s.done and mint or gold),
				lines={"Reward: +"..fmt(num(r.xp,0)).." "..escape(tostring(r.skill or t.skill)).." XP   ·   +"..fmt(num(r.coins,0)).." coins   ·   "..paint("+"..fmt(num(r.dust,0)).." "..CL.DUST.name,CL.DUST.color)},
				bar={fraction=progress/math.max(1,amount),color=s.done and mint or rgb(CL.DUST.color),caption=fmt(progress).." / "..fmt(amount)},actions=actions})
		end
	end
	if #slots==0 then card({name="CommissionsEmpty",motif="Journal",title="The board is being drawn…",detail="Open the atlas again in a moment."}) end
	heading("COMMISSION MILESTONES    /    "..fmt(num(c.total,0)).." COMPLETED")
	local lines={}
	for i,m in ipairs(CL.Milestones) do
		local met=num(c.milestone,0)>=i
		table.insert(lines,(met and check or cross).." "..paint(m.at,met and "8EE6CB" or "F3C66E").."  "..escape(m.name).." — "..escape(m.text))
	end
	-- The Paragon title (last milestone) is worn from here, like a log tab title.
	local paragon=type(c.paragon)=="string" and c.paragon or CL.milestonePerks(num(c.total,0)).title
	local titleActions=nil
	if paragon and logs then
		if g.title=="Paragon" then titleActions={{caption="Remove title",name="LogTitleParagonOff",fn=function() send("logTitle","none") end}}
		else titleActions={{caption="Wear "..paragon,name="LogTitleParagon",primary=true,fn=function() send("logTitle","Paragon") end}} end
	end
	card({name="CommissionMilestones",motif="Hero",title="Milestones",titleColor=gold,subtitle="Permanent perks for completed commissions",
		pips={total=#CL.Milestones,filled=num(c.milestone,0),color=mint},lines=lines,actions=titleActions})
	heading("FORGEHEART    /    GLIMMERDUST PERKS")
	local levels=tbl(c.forge)
	local costs=tbl(c.costs)
	for _,id in ipairs(CL.ForgeOrder) do
		local f=CL.Forge[id]
		local lvl=num(levels[id],0)
		local cost=costs[id]
		local value=CL.forgeValue(id,lvl)
		local shown=f.stat=="gemChance" and (string.format("%.2f",value).."% gem chance") or ("+"..value.." "..(Data.Stats[f.stat] and Data.Stats[f.stat].name or f.stat))
		local afford=type(cost)=="number" and num(c.dust,0)>=cost
		card({name="Forge"..id,motif="Workshop",accent=rgb(f.color),title=escape(f.name),titleColor=rgb(f.color),
			subtitle="Level "..lvl.." / "..f.max.."   ·   "..shown,detail=escape(f.text),
			lines={id=="HearthglowFortune" and ("Active now: +"..fmt(num(c.fortune,0)).." Mining Fortune (Mastery and Forgeheart share 99).") or nil,
				id=="Gemseeker" and ("Total gem chance per Mining harvest: "..string.format("%.2f",num(c.gemChance,0)).."%.") or nil},
			pips={total=f.max,filled=lvl,color=rgb(f.color)},
			actions={{caption=type(cost)=="number" and ("Forge "..fmt(cost)) or "Mastered",name="ForgeBuy"..id,primary=afford,disabled=not afford,
				reason=type(cost)=="number" and ("Needs "..fmt(cost).." "..CL.DUST.name..".") or "Fully forged.",fn=function() send("forgeBuy",id) end}}})
	end
end
function CLP.drawLog()
	if not CLP.ready() then dataMissing() return end
	local CL=Data.CommissionsLogs
	local L=CL.log()
	local logs=CLP.logs()
	local g=tbl(tbl(logs).log)
	local counts=tbl(g.counts)
	local actions={}
	if type(g.title)=="string" and g.title~="" then table.insert(actions,{caption="Remove title",name="LogTitleNone",fn=function() send("logTitle","none") end}) end
	card({name="LogSummary",motif="Journal",accent=gold,title="Collection Log",titleColor=gold,
		subtitle=fmt(num(g.found,0)).." of "..fmt(L.total).." entries   ·   score "..fmt(num(g.score,0)).." / "..fmt(num(g.max,0)),
		badge=logs and string.upper(tostring(g.rank or "Driftling")) or "SYNCING",badgeColor=mint,
		detail="Every pet, unique and rare drop in the isles, logged the first time it reaches your satchel. Complete a tab for coins and a title.",
		lines={(type(g.titleText)=="string" and g.titleText~="") and ("Title worn: "..paint(escape(g.titleText),"F3C66E")) or nil,
			num(g.retro,0)>0 and ("Credited from your satchel when the log opened: "..fmt(num(g.retro,0)).." entries.") or nil},
		bar={fraction=num(g.found,0)/math.max(1,L.total),color=gold,caption=fmt(num(g.found,0)).." / "..fmt(L.total)},actions=actions})
	if not CLP.tab or not L.Tabs[CLP.tab] or #L.Tabs[CLP.tab]==0 then CLP.tab=L.Order[1] end
	local names={}
	for _,tab in ipairs(L.Order) do table.insert(names,tab) end
	sectionBar(names,CLP.tab,function(name) CLP.tab=name render() end,{small=true,prefix="LogTab"})
	local tab=CLP.tab
	if not tab then return end
	local def=CL.LogTabs[tab]
	local list=L.Tabs[tab]
	local found=0
	for _,id in ipairs(list) do if num(counts[id],0)>0 then found+=1 end end
	local claimed=tbl(g.claimed)[tab]==true
	local tabActions={}
	if claimed then
		if g.title~=tab then table.insert(tabActions,{caption="Wear title",name="LogTitle"..tab,fn=function() send("logTitle",tab) end}) end
	else
		table.insert(tabActions,{caption="Claim",name="LogClaim"..tab,primary=found==#list,disabled=found<#list,reason="Log every "..def.name.." entry first.",fn=function() send("logClaim",tab) end})
	end
	card({name="LogTab"..tab.."Card",motif="Journal",accent=rgb(def.color),title=escape(def.name),titleColor=rgb(def.color),
		subtitle=found.." / "..#list.." logged",badge=claimed and "CLAIMED" or (found==#list and "COMPLETE" or nil),badgeColor=mint,
		lines={"Completion reward: +"..fmt(def.coins).." coins and the "..paint(escape(def.title),"F3C66E").." title."},
		bar={fraction=found/math.max(1,#list),color=rgb(def.color),caption=found.." / "..#list},actions=tabActions})
	local cell=compactAtlas and 62 or 72
	CLP.grid("LogGrid"..tab,list,cell,function(grid,i,id)
		local n=num(counts[id],0)
		local b=tile(grid,"LogEntry"..id,i,function() notify(itemName(id)..(n>0 and (" — logged x"..fmt(n)) or " — not yet logged")) end)
		itemIcon(b,id,compactAtlas and 34 or 40,n<=0).Position=UDim2.new(.5,-(compactAtlas and 17 or 20),0,4)
		local foot=label(b,n>0 and ("x"..fmt(n)) or "?",2,cell-18,UDim.new(1,-4),16,UI.heavy,11,n>0 and mint or muted)
		foot.TextXAlignment=Enum.TextXAlignment.Center
	end)
end
-- Mirrors the server's Logs.donateCheck: worn, bagged and upgraded copies are
-- held back; a donation is refused only when it would take one of them.
function CLP.donatable(id)
	local have=num(tbl(state.items)[id],0)
	if have<1 then return false,"You do not own one." end
	local worn,bagged=0,0
	for _,eq in pairs(tbl(dget("equipment"))) do if eq==id then worn+=1 end end
	for _,b in ipairs(tbl(dget("accessoryBag"))) do if b==id then bagged+=1 end end
	local gear=tbl(dget("gear"))
	local upgraded=tbl(gear.reforges)[id]~=nil or num(tbl(gear.stars)[id],0)>0 or tbl(gear.books)[id]~=nil or next(tbl(tbl(dget("enchants"))[id]))~=nil
	if have>math.max(worn+bagged,upgraded and 1 or 0) then return true end
	if worn>0 then return false,"Unequip it first (or donate a spare copy)." end
	if bagged>0 then return false,"Take it out of your accessory bag first (or donate a spare copy)." end
	return false,"It carries upgrades; donate a spare copy instead."
end
function CLP.drawMuseum()
	if not CLP.ready() then dataMissing() return end
	local CL=Data.CommissionsLogs
	local M=CL.museum()
	local logs=CLP.logs()
	local mu=tbl(tbl(logs).museum)
	local donated=tbl(mu.donated)
	local reached=num(mu.milestone,0)
	local nextM=CL.MuseumMilestones[reached+1]
	local perkLines={}
	for stat,v in pairs(tbl(mu.stats)) do table.insert(perkLines,"+"..fmt(v).." "..(Data.Stats[stat] and Data.Stats[stat].name or stat)) end
	table.sort(perkLines)
	card({name="MuseumSummary",motif="Journal",accent=rgb("C77DFF"),title="Aether Museum",titleColor=gold,
		subtitle=fmt(num(mu.count,0)).." of "..fmt(M.total).." on display",badge=logs and (reached.." / "..#CL.MuseumMilestones) or "SYNCING",badgeColor=mint,
		detail="Donate one of each weapon, armor piece, rarity, mineral and trophy. Donations are kept by the Museum for good (the item is consumed); equipped, bagged or upgraded last copies are refused.",
		lines={nextM and ("Next milestone at "..nextM.at..": +"..fmt(nextM.coins).." coins and permanent stats.") or "Every milestone reached.",
			#perkLines>0 and ("Museum perks: "..table.concat(perkLines,", ")) or nil},
		pips={total=#CL.MuseumMilestones,filled=reached,color=rgb("C77DFF")}})
	sectionBar(CL.MuseumOrder,CLP.cat,function(name) CLP.cat=name CLP.pick=nil render() end,{small=true,prefix="MuseumCat"})
	local cat=CLP.cat
	local list=M.Cats[cat] or {}
	if CLP.pick and itemDef(CLP.pick) and not donated[CLP.pick] then
		local id=CLP.pick
		local okay,why=CLP.donatable(id)
		card({name="MuseumPick",item=id,title=escape(itemName(id)),titleColor=rgb(rarityHex(itemDef(id).rarity)),subtitle="Donate to the "..CL.MuseumCategories[cat].name.." wing?",
			detail=okay and "One copy is consumed and displayed forever." or why,
			actions={{caption="Donate",name="MuseumDonate",primary=okay,disabled=not okay,reason=why,fn=function() CLP.pick=nil send("museumDonate",id) end},
				{caption="Cancel",name="MuseumCancel",fn=function() CLP.pick=nil render() end}}})
	end
	local have=0
	for _,id in ipairs(list) do if donated[id] then have+=1 end end
	heading(string.upper(CL.MuseumCategories[cat].name).."    /    "..have.." OF "..#list.." DISPLAYED")
	local cell=compactAtlas and 62 or 72
	CLP.grid("MuseumGrid"..cat,list,cell,function(grid,i,id)
		local shown=donated[id]==true
		local owned=num(tbl(state.items)[id],0)>0
		local b=tile(grid,"MuseumItem"..id,i,function()
			if shown then notify(itemName(id).." is on display.") return end
			if not owned then notify(itemName(id).." — not owned yet.") return end
			CLP.pick=id
			render()
		end)
		itemIcon(b,id,compactAtlas and 34 or 40,not shown and not owned).Position=UDim2.new(.5,-(compactAtlas and 17 or 20),0,4)
		if owned and not shown then make("UIStroke",b,{Color=gold,Thickness=1.5,Transparency=.1}) end
		local foot=label(b,shown and "✓" or (owned and "donate" or "?"),2,cell-18,UDim.new(1,-4),16,UI.heavy,11,shown and mint or (owned and gold or muted))
		foot.TextXAlignment=Enum.TextXAlignment.Center
	end)
end
Pages.drawCommissions,Pages.drawCollectionLog,Pages.drawMuseum=CLP.drawCommissions,CLP.drawLog,CLP.drawMuseum
end

------------------------------------------------------------------------------
-- Workshop › Crafting (Crafting team): the Jeweller's Bench, Tanning Rack and
-- Glass Furnace (Data.Crafting). A station switcher, a summary card (level,
-- presence at the station, owned tools), the running batch (progress, Stop)
-- and pattern cards per category with batch buttons (×1, ×5, ×all ≤ 28). The
-- server (craftBatch "recipe:count") paces and validates every action; the
-- client only previews gates. Snapshot key `crafting`. State lives in Pages.CR.
------------------------------------------------------------------------------
do
local CRP={station="Jeweller",category={}}
Pages.CR=CRP
local function CRD() return Data and type(Data.Crafting)=="table" and Data.Crafting or nil end
function CRP.snap() return tbl(state.crafting) end
function CRP.levelOf(skill)
	local info=skillsOf(state)[skill]
	return info and info.level or 1
end
function CRP.tierOf(id) local _,tier=collectionInfo(id) return tier end
-- The journal as CR.check / CR.affordable read it: items plus worn gear and the
-- accessory bag, whose copies the server never spends (CR.spare).
function CRP.journal()
	local d=tbl(state.depth)
	return {items=tbl(state.items),equipment=tbl(d.equipment),accessoryBag=tbl(d.accessoryBag)}
end
-- How many actions the satchel can fund right now (spare copies, capped at the batch size).
function CRP.affordable(rec)
	local CR=CRD()
	if CR and CR.affordable then return CR.affordable(CRP.journal(),rec) end
	local n=CR and CR.MAX_BATCH or 28
	for id,need in pairs(tbl(rec.costs)) do n=math.min(n,math.floor(count("items",id)/math.max(1,num(need,1)))) end
	return math.max(0,n)
end
-- Batch buttons for `afford` actions: ×1 always, ×5 and ×afford when they differ.
function CRP.batchSizes(afford)
	local sizes={1}
	if afford>=5 then table.insert(sizes,5) end
	if afford>1 and afford~=5 then table.insert(sizes,afford) end
	return sizes
end
function CRP.categories(list)
	local cats,by={},{}
	for _,rec in ipairs(list) do
		local c=rec.category or "Patterns"
		if not by[c] then by[c]={};table.insert(cats,c) end
		table.insert(by[c],rec)
	end
	return cats,by
end
function CRP.outputLine(def)
	if not def then return "" end
	local parts={}
	if def.stats then table.insert(parts,statText(def.stats)) end
	if def.kind=="accessory" then table.insert(parts,paint("✧ "..tostring(tbl(tbl(Data.Rarity)[def.rarity]).power or "?").." Magical Power","FFAA00")..(def.gem and " (best of its gem family only)" or "")) end
	if def.kind=="armor" and def.set and Data.Sets and Data.Sets[def.set] then table.insert(parts,"Set: "..escape(tostring(Data.Sets[def.set].text))) end
	if type(def.requires)=="table" then
		for skill,lvl in pairs(def.requires) do table.insert(parts,"Wear: "..escape(skill).." "..fmt(lvl)) end
	end
	return table.concat(parts,"  ·  ")
end
function CRP.draw()
	local CR=CRD()
	if not CR then dataMissing() return end
	local snap=CRP.snap()
	local at=type(snap.station)=="string" and snap.station or ""
	if CR.Stations[at] and CRP.lastVisit~=at then CRP.station=at end
	CRP.lastVisit=at
	if not CR.Stations[CRP.station] then CRP.station=CR.StationOrder[1] end
	local names,ids={},{}
	for _,id in ipairs(CR.StationOrder) do table.insert(names,CR.Stations[id].name);ids[CR.Stations[id].name]=id end
	sectionBar(names,CR.Stations[CRP.station].name,function(name) CRP.station=ids[name];scroll.CanvasPosition=Vector2.zero;render() end,{small=true,prefix="Station"})
	local st=CR.Stations[CRP.station]
	local info=skillsOf(state).Crafting
	-- Present = a live visit to this station AND standing in range (snap.near),
	-- exactly what the server's craftBatch requires.
	local here=at==CRP.station and snap.near~=false
	local presence=if here then paint("At the "..st.name.." · batches open for "..clock(num(snap.stationIn,0)),"9EE7D2")
		else paint("Visit the "..st.name.." on the Guild Terrace (Artificers' Row) to craft here.","E8806A")
	local tools={}
	for _,id in ipairs(CR.ToolOrder) do
		local used=false
		for _,b in pairs(CR.Branches) do if b.station==CRP.station and b.tool==id then used=true end end
		for _,rec in ipairs(CR.stationRecipes(CRP.station)) do if rec.tool==id then used=true end end
		if used then table.insert(tools,(count("items",id)>0 and check or cross).." "..escape(itemName(id))) end
	end
	card({name="CraftingStation",motif="Workshop",accent=rgb(st.color),title=escape(st.name),titleColor=gold,
		subtitle=info and ("Crafting "..info.level.." / "..maxLevel()) or nil,detail=st.text,
		bar=info and {fraction=info.fraction,color=rgb(skillHex("Crafting")),caption=info.maxed and "MAX LEVEL" or (fmt(math.max(0,info.ceiling-info.xp)).." XP to Crafting "..(info.level+1))} or nil,
		lines={presence,#tools>0 and ("Tools: "..table.concat(tools,"   ")) or "",num(snap.shattered,0)>0 and ("Gems shattered so far: "..fmt(snap.shattered)) or ""}})
	local job=type(snap.job)=="table" and snap.job or nil
	if job and CR.Recipes[job.recipe] then
		local rec=CR.Recipes[job.recipe]
		local total=math.max(1,num(job.total,1))
		card({name="CraftingJob",item=rec.output,title="Crafting "..escape(itemName(rec.output)),titleColor=rgb(itemHex(rec.output)),
			subtitle=fmt(num(job.done,0)).." / "..fmt(total).."  ·  "..rec.seconds.."s each",
			lines={"+"..fmt(num(job.made,0)).." made"..(num(job.shattered,0)>0 and ("  ·  "..fmt(job.shattered).." shattered") or "").."  ·  +"..fmt(num(job.xp,0)).." "..escape(rec.skill).." XP"},
			bar={fraction=math.clamp(num(job.done,0)/total,0,1),color=mint,caption="Next in "..string.format("%.1f",num(job.nextIn,0)).."s · stay at the station"},
			actions={{caption="Stop",fn=function() send("craftStop") end}}})
	end
	local cats,by=CRP.categories(CR.stationRecipes(CRP.station))
	local cat=CRP.category[CRP.station]
	if not table.find(cats,cat) then cat=cats[1] end
	CRP.category[CRP.station]=cat
	if #cats>1 then sectionBar(cats,cat,function(name) CRP.category[CRP.station]=name;scroll.CanvasPosition=Vector2.zero;render() end,{small=true,prefix="Category"}) end
	local craftLevel=CRP.levelOf("Crafting")
	for _,rec in ipairs(by[cat] or {}) do
		local out=itemDef(rec.output)
		local ok,reason=CR.check(CRP.journal(),rec.id,CRP.levelOf,CRP.tierOf)
		local gates={(CRP.levelOf(rec.skill)>=rec.level and check or cross).." "..escape(rec.skill).." "..rec.level}
		if rec.tool then table.insert(gates,(count("items",rec.tool)>0 and check or cross).." "..escape(itemName(rec.tool))) end
		for id,tier in pairs(tbl(rec.collectionTier)) do table.insert(gates,(CRP.tierOf(id)>=tier and check or cross).." "..escape(itemName(id)).." collection "..numeral(tier)) end
		local needs={}
		for id,n in pairs(tbl(rec.costs)) do
			local have=count("items",id)
			table.insert(needs,paint(fmt(have).."/"..fmt(n),have>=n and "9EE7D2" or "E8806A").." "..paint(escape(itemName(id)),itemHex(id)))
		end
		table.sort(needs)
		local lines={table.concat(gates,"   "),"Needs "..table.concat(needs,"  ·  ")}
		local summary=CRP.outputLine(out)
		if summary~="" then table.insert(lines,summary) end
		local xpLine=paint("+"..fmt(rec.xp).." "..escape(rec.skill).." XP","F9CC77").."  ·  "..rec.seconds.."s per action"
		local shatter=CR.cutFailChance(rec,craftLevel)
		if shatter>0 then xpLine..="  ·  "..paint(string.format("%.0f%% shatter",shatter*100),"E8806A") end
		table.insert(lines,xpLine)
		local afford=CRP.affordable(rec)
		local blocked=not ok or not here
		local why=reason or (not here and (if at==CRP.station then "Stand at the "..st.name.." to craft." else "Visit the "..st.name.." first.")) or nil
		local actions={}
		for _,n in ipairs(CRP.batchSizes(afford)) do
			table.insert(actions,{caption=n==1 and "Craft ×1" or "×"..n,primary=n==1 and not blocked or nil,disabled=blocked,reason=why,fn=function() send("craftBatch",rec.id..":"..n) end})
		end
		card({name="Craft"..rec.id,item=rec.output,title=escape(out and out.name or rec.output)..(rec.amount>1 and ("  ×"..rec.amount) or ""),titleColor=rgb(itemHex(rec.output)),
			subtitle=escape((out and out.rarity or "").." "..kindLabel(out)).."  ·  Lv "..rec.level,badge=ok and "READY" or nil,badgeColor=mint,lines=lines,actions=actions})
	end
end
Pages.drawCrafting=CRP.draw
end
------------------------------------------------------------------------------
-- Workshop › Beaconry (Beaconry team; docs/DEPTH-CONTRACT.md §37). Sections:
-- Kindle (a summary card, your campfires, one card per log with Kindle),
-- Campfire (cooking at the nearest lit campfire: running batch + recipe
-- cards with ×1 / ×5 / ×all), Beacons (the nine pyres, their state and a
-- waypoint, the weekly community watch and its claim). The server validates
-- and paces everything (verbs kindle, fireCook, fireStop, beaconClaim; beacon
-- pyres are lit at the pyre's prompt). Snapshot key `beaconry`. State: Pages.BC.
------------------------------------------------------------------------------
do
local BCP={section="Kindle"}
Pages.BC=BCP
local function BD() return Data and type(Data.Beaconry)=="table" and Data.Beaconry or nil end
function BCP.snap() return tbl(state.beaconry) end
function BCP.levelOf(skill)
	local info=skillsOf(state)[skill]
	return info and info.level or 1
end
-- QC: the server-wide count and your lifetime kindles read as separate facts.
function BCP.burningLine(snap)
	local B=BD()
	local kindled=0
	for _,n in pairs(tbl(snap.kindled)) do kindled+=num(n,0) end
	return fmt(num(snap.burning,0)).."/"..fmt(B and B.MAX_FIRES or 40).." campfires burning on this server  ·  "..fmt(kindled).." kindled  ·  "
		..fmt(num(snap.ash,0)).." ash gathered  ·  "..fmt(num(snap.failed,0)).." sparks that failed"
end
function BCP.cookAfford(rec)
	local B=BD()
	local n=B and B.MAX_BATCH or 28
	for id,need in pairs(tbl(rec.costs)) do n=math.min(n,math.floor(count("items",id)/math.max(1,num(need,1)))) end
	return math.max(0,n)
end
local function guide(specs,label)
	local request=player:FindFirstChild("WayfinderRequest")
	if request then request:Fire(specs,label) else notify("The Wayfinder is still charting the isles. Try again in a moment.") end
end
local function drawKindle(B,snap)
	local lvl=BCP.levelOf("Beaconry")
	local strikerId=type(snap.striker)=="string" and snap.striker or nil
	local striker=strikerId and B.Strikers[strikerId] or nil
	local mine=type(snap.fires)=="table" and snap.fires or {}
	local fireLines={}
	for _,f in ipairs(mine) do
		if type(f)=="table" then table.insert(fireLines,paint(escape(itemName(f.log)),itemHex(f.log)).."  "..clock(num(f.left,0)).." left") end
	end
	local cooldown=num(snap.kindleIn,0)
	card({name="BeaconryKindle",motif="Workshop",accent=rgb(skillHex("Beaconry")),title="Kindling",titleColor=gold,
		subtitle=(striker and (check.." "..escape(itemName(strikerId))) or (cross.." No striker: forge a Flint Striker (Smithing 1)"))
			..(snap.everflame and "  ·  "..paint("EVERFLAME","FFB347") or ""),
		detail="Kindle a log on open ground (never on paths, bridges or another wayfarer's island). A campfire burns for a while, then leaves Pyre Ash. Cook on any lit campfire.",
		lines={#fireLines>0 and ("Your campfires: "..table.concat(fireLines,"   ")) or "No campfire of yours is burning.",
			BCP.burningLine(snap)},
		bar=cooldown>0 and {fraction=math.clamp(1-cooldown/B.KINDLE_SECONDS,0,1),color=mint,caption="Striker ready in "..string.format("%.1f",cooldown).."s"} or nil,
		actions={{caption="Kindle best log",primary=striker~=nil or nil,disabled=striker==nil,reason="Forge a Flint Striker first.",fn=function() send("kindle","") end}}})
	heading("LOGS")
	for _,log in ipairs(B.Logs) do
		local have=count("items",log.id)
		local chance=if snap.everflame then 1 else B.successChance(lvl,log,striker and striker.tier or 1)
		local ok=lvl>=log.level and have>0 and striker~=nil
		local why=(lvl<log.level and ("Requires Beaconry "..log.level..".")) or (striker==nil and "Forge a Flint Striker first.") or (have<=0 and ("You have no "..log.name..".")) or nil
		card({name="Kindle"..log.id,item=log.id,title=escape(log.name),titleColor=rgb(itemHex(log.id)),
			subtitle="Lv "..log.level.."  ·  +"..fmt(log.xp).." XP  ·  burns "..log.seconds.."s",badge=ok and "READY" or nil,badgeColor=mint,
			lines={(lvl>=log.level and check or cross).." Beaconry "..log.level.."   "..paint(fmt(have).." in satchel",have>0 and "9EE7D2" or "E8806A"),
				lvl>=log.level and ("Kindle chance "..paint(math.floor(chance*100+.5).."%",chance>=1 and "9EE7D2" or "F9CC77")) or ""},
			actions={{caption="Kindle",primary=ok or nil,disabled=not ok,reason=why,fn=function() send("kindle",log.id) end}}})
	end
end
local function drawCampfire(B,snap)
	local near=type(snap.near)=="table" and snap.near or nil
	local cookLevel=BCP.levelOf("Cooking")
	card({name="BeaconryCampfire",motif="Workshop",accent=rgb(skillHex("Cooking")),title="Campfire cooking",titleColor=gold,
		subtitle=near and paint("At a campfire ("..escape(itemName(near.log))..") · "..clock(num(near.left,0)).." left","9EE7D2")
			or paint("Stand beside a lit campfire to cook on it.","E8806A"),
		detail="Cooking's meals and feasts cook here too: +"..math.floor((B.FIRE_XP_MULT-1)*100+.5).."% Cooking XP, but open flames burn food until you outgrow the recipe. Two dishes only a campfire can make.",
		lines={"Cooked "..fmt(num(snap.cooked,0)).."  ·  burnt "..fmt(num(snap.burnt,0))}})
	local job=type(snap.job)=="table" and snap.job or nil
	local jobRec=job and B.cookRecipe(job.recipe)
	if jobRec then
		local total=math.max(1,num(job.total,1))
		card({name="BeaconryJob",item=jobRec.output,title="Cooking "..escape(itemName(jobRec.output)),titleColor=rgb(itemHex(jobRec.output)),
			subtitle=fmt(num(job.done,0)).." / "..fmt(total).."  ·  "..B.COOK_SECONDS.."s each",
			lines={"+"..fmt(num(job.cooked,0)).." cooked"..(num(job.burnt,0)>0 and ("  ·  "..fmt(job.burnt).." burnt") or "").."  ·  +"..fmt(num(job.xp,0)).." Cooking XP"},
			bar={fraction=math.clamp(num(job.done,0)/total,0,1),color=mint,caption="Next in "..string.format("%.1f",num(job.nextIn,0)).."s · stay by the fire"},
			actions={{caption="Stop",fn=function() send("fireStop") end}}})
	end
	heading("RECIPES")
	for _,rec in ipairs(B.cookList()) do
		local out=itemDef(rec.output)
		local needs={}
		for id,n in pairs(tbl(rec.costs)) do
			local have=count("items",id)
			table.insert(needs,paint(fmt(have).."/"..fmt(n),have>=n and "9EE7D2" or "E8806A").." "..paint(escape(itemName(id)),itemHex(id)))
		end
		table.sort(needs)
		local burn=B.burnChance(cookLevel,rec)
		local afford=BCP.cookAfford(rec)
		local ok=cookLevel>=rec.level and afford>0
		local blocked=not ok or near==nil
		local why=(cookLevel<rec.level and ("Requires Cooking "..rec.level..".")) or (afford<=0 and "Missing ingredients.") or (near==nil and "Stand beside a lit campfire.") or nil
		local actions={}
		local sizes={1}
		if afford>=5 then table.insert(sizes,5) end
		if afford>1 and afford~=5 then table.insert(sizes,afford) end
		for _,n in ipairs(sizes) do
			table.insert(actions,{caption=n==1 and "Cook ×1" or "×"..n,primary=n==1 and not blocked or nil,disabled=blocked,reason=why,fn=function() send("fireCook",rec.id..":"..n) end})
		end
		card({name="Fire"..rec.id,item=rec.output,title=escape(out and out.name or rec.output)..(rec.fireOnly and "  ·  "..paint("CAMPFIRE ONLY","FFB347") or ""),titleColor=rgb(itemHex(rec.output)),
			subtitle="Cooking "..rec.level.."  ·  +"..fmt(B.cookXp(rec)).." XP",badge=(ok and near) and "READY" or nil,badgeColor=mint,
			lines={(cookLevel>=rec.level and check or cross).." Cooking "..rec.level..(burn>0 and ("   "..paint(string.format("%.0f%% burn",burn*100),"E8806A")) or ("   "..paint("never burns","9EE7D2"))),
				"Needs "..table.concat(needs,"  ·  ")},actions=actions})
	end
end
local function drawBeacons(B,snap)
	local week=tbl(snap.week)
	local total,goal=num(week.total,0),math.max(1,num(week.goal,B.WEEK_GOAL))
	card({name="BeaconryWeek",motif="Workshop",accent=rgb("FFB347"),title="The weekly watch",titleColor=gold,
		subtitle=fmt(total).." / "..fmt(goal).." beacons lit across the isles this week",
		detail="Every beacon lit on any server counts. Light at least one this week; when the isles reach the goal, claim Beaconry XP.",
		lines={"You lit "..fmt(num(week.lit,0)).." this week  ·  "..fmt(num(snap.weeks,0)).." watches kept  ·  resets in "..clock(num(week.resetIn,0))},
		bar={fraction=math.clamp(total/goal,0,1),color=rgb("FFB347"),caption=total>=goal and "GOAL REACHED" or (fmt(goal-total).." to go")},
		actions={{caption=week.claimed and "Claimed" or "Claim",primary=week.canClaim==true or nil,disabled=week.canClaim~=true,
			reason=week.claimed and "Already claimed this week." or "Light a beacon and help reach the goal first.",fn=function() send("beaconClaim") end}}})
	heading("BEACON NETWORK")
	local lvl=BCP.levelOf("Beaconry")
	local burning=tbl(snap.beacons)
	for _,id in ipairs(B.BeaconOrder) do
		local b=B.Beacons[id]
		local left=num(burning[id],0)
		local region=Data.RegionById and Data.RegionById[b.region]
		local parts={}
		for stat,v in pairs(b.buff) do table.insert(parts,"+"..v.." "..escape(tbl(tbl(Data.Stats)[stat]).name or stat)) end
		table.sort(parts)
		card({name="Beacon"..id,item=b.log,accent=rgb(b.color),title=escape(b.name),titleColor=rgb(b.color),
			subtitle=escape(region and region.name or b.region).."  ·  Beaconry "..b.level,
			badge=left>0 and ("BURNING "..clock(left)) or "DARK",badgeColor=left>0 and rgb("FFB347") or muted,
			lines={(lvl>=b.level and check or cross).." Beaconry "..b.level.."   Feed "..B.BEACON_LOGS.." "..escape(itemName(b.log)).." or better  ·  +"..fmt(B.beaconXp(B.LogById[b.log])).." XP",
				"Warmth ("..math.floor(B.WARMTH_SECONDS/60).." min): "..table.concat(parts,", ").."  ·  lit "..fmt(num(tbl(snap.lit)[id],0)).."×"},
			actions={{caption="Waypoint",fn=function() guide({"anchor:Waypoint_Beacon_"..id,"region:"..b.region},b.name) end}}})
	end
end
function BCP.draw()
	local B=BD()
	if not B then dataMissing() return end
	local snap=BCP.snap()
	local info=skillsOf(state).Beaconry
	if info then
		card({name="BeaconrySummary",motif="Workshop",accent=rgb(skillHex("Beaconry")),title="Beaconry",titleColor=gold,
			subtitle="Level "..info.level.." / "..maxLevel(),
			bar={fraction=info.fraction,color=rgb(skillHex("Beaconry")),caption=info.maxed and "MAX LEVEL" or (fmt(math.max(0,info.ceiling-info.xp)).." XP to Beaconry "..(info.level+1))}})
	end
	local sections={"Kindle","Campfire","Beacons"}
	if not table.find(sections,BCP.section) then BCP.section="Kindle" end
	sectionBar(sections,BCP.section,function(name) BCP.section=name;scroll.CanvasPosition=Vector2.zero;render() end,{small=true,prefix="Beaconry"})
	if BCP.section=="Campfire" then drawCampfire(B,snap) elseif BCP.section=="Beacons" then drawBeacons(B,snap) else drawKindle(B,snap) end
end
Pages.drawBeaconry=BCP.draw
end
------------------------------------------------------------------------------
-- Workshop › Contests and Hunt › Trophies (Contests team; docs/DEPTH-CONTRACT.md
-- §39), plus the contest tracker HUD (right column, during a contest).
-- Workshop › Contests sections: Contest (the running contest: countdown,
-- featured crops with Enter, your score, the live bracket estimate, the top
-- entries per crop; the next contest), Exchange (Harvest Medals: gear, the
-- Furrow Almanac, titles) and Records (personal bests, brackets won, recent
-- results). Hunt › Trophies sections: Ledger (the fifteen trophy fish, their
-- waters and conditions, the qualities caught), Rewards (the Trophy Keeper's
-- ledger tiers, titles) and Bait. The schedule and every rule come from
-- Data.Contests / Data.Trophies (deterministic); scores, estimates and
-- records from snapshot.contests / snapshot.trophies. State: Pages.CT.
------------------------------------------------------------------------------
do
local CTP={section="Contest",tsection="Ledger",timers={},boundary=math.huge}
Pages.CT=CTP
local function CD() return Data and type(Data.Contests)=="table" and Data.Contests or nil end
local function TD() return Data and type(Data.Trophies)=="table" and Data.Trophies or nil end
function CTP.now()
	local ok,t=pcall(function() return workspace:GetServerTimeNow() end)
	if ok and type(t)=="number" and t==t and t>1577836800 then return math.floor(t) end
	local snap=num(tbl(state.contests).now,0)
	return math.floor(if snap>1577836800 then snap else os.time())
end
function CTP.timer(fn,color)
	return function(body,nextOrder)
		local copy=para(body,fn(CTP.now()),nextOrder(),color or gold,compactAtlas and 13 or 14)
		copy.Name="Countdown"
		table.insert(CTP.timers,{label=copy,fn=fn})
	end
end
-- A round medallion icon (fish and brackets are not satchel items).
function CTP.medallion(hex,glyph)
	return function(band,size)
		local disc=make("TextLabel",band,{Name="Medallion",Size=UDim2.fromOffset(size,size),BackgroundColor3=safeColor(hex,gold),BackgroundTransparency=.55,
			Text=glyph or "◆",TextSize=math.floor(size*.5),Font=Enum.Font.GothamBold,TextColor3=ivory,BorderSizePixel=0})
		make("UICorner",disc,{CornerRadius=UDim.new(1,0)})
		make("UIStroke",disc,{Color=safeColor(hex,gold),Thickness=2})
		return disc
	end
end
function CTP.bracketText(id)
	local CT=CD()
	local b=CT and CT.BracketById[id]
	return if b then paint(string.upper(b.name),b.color) else paint("NO BRACKET YET","B9C7CC")
end
-- The running contest (the snapshot's while it holds, else the client's clock).
function CTP.contest()
	local CT=CD()
	local now=CTP.now()
	local at=CT.at(now)
	local s=tbl(state.contests)
	local entry=type(s.entry)=="table" and num(s.k,-1)==at.k and s.entry or nil
	return at,s,entry,now
end
local function drawContest(CT,s)
	local at,_,entry,now=CTP.contest()
	CTP.boundary=if at.active then at.ends else at.nextWindow.starts
	local cropNames={}
	for _,id in ipairs(at.crops) do table.insert(cropNames,paint(escape(itemName(id)),itemHex(id))) end
	if at.active then
		local lines={"Featured: "..table.concat(cropNames,"  ·  ")}
		if entry then
			local def=CT.CropById[entry.c]
			table.insert(lines,"Your entry: "..paint(escape(itemName(entry.c)),itemHex(entry.c)).."  ·  "..paint(fmt(num(entry.s,0)),"FFF4D9").." harvested"
				..(def and num(entry.s,0)<def.min and paint("  ·  "..fmt(def.min).." to place","E9C46A") or ""))
			local est=type(s.estimate)=="table" and s.estimate or nil
			if est then
				table.insert(lines,"Live estimate: "..CTP.bracketText(est.bracket).."  ·  about #"..fmt(num(est.rank,0)).." of "..fmt(num(est.n,0)).." placing entrants")
			elseif num(entry.s,0)>0 then
				table.insert(lines,paint("Gathering every isle's ledgers for a live estimate…","B9C7CC"))
			end
		else
			table.insert(lines,"Harvest a featured crop to enter, or choose one below.")
		end
		card({name="ContestNow",icon=CTP.medallion(CT.COLOR,"🌾"),accent=rgb(CT.COLOR),title=paint("HARVEST CONTEST  ·  RUNNING",CT.COLOR),
			subtitle="Contest #"..fmt(at.k).."  ·  one crop per entry  ·  every isle on one ledger",badge=entry and paint("ENTERED","9EE7D2") or paint("OPEN","F7C548"),
			lines=lines,after=CTP.timer(function(t) return "The bell rings in "..CT.span(at.ends-t) end)})
		heading("FEATURED CROPS    /    ENTER ONE")
		for slot,id in ipairs(at.crops) do
			local def=CT.CropById[id]
			local mine=entry and entry.c==id
			local locked=entry and num(entry.s,0)>0 and not mine
			local reason=(mine and "You are competing with this crop.") or (locked and "Entries lock once you score.") or nil
			local rows={}
			local boardRows=tbl(tbl(s.board)[slot])
			for i,row in ipairs(boardRows) do
				if i>CT.LB_TOP then break end
				if type(row)~="table" then continue end
				local who=escape(type(row.n)=="string" and row.n or "Wayfarer")
				table.insert(rows,paint("#"..i,"B9C7CC").."  "..(row.me and paint(who,"9EE7D2") or who).."  "..paint(fmt(num(row.s,0)),"FFF4D9"))
			end
			if #rows==0 then table.insert(rows,paint("No scores on the ledger yet.","B9C7CC")) end
			table.insert(rows,1,"Places from "..fmt(def and def.min or 0).."  ·  your best "..fmt(num(tbl(s.best)[id],0)))
			card({name="ContestCrop"..id,item=id,accent=mine and gold or nil,edge=mine and gold or nil,title=escape(itemName(id)),titleColor=rgb(itemHex(id)),
				subtitle=(def and def.exclusive) and "Verdant Garden crop" or "Field and garden crop",badge=mine and paint("YOUR ENTRY","9EE7D2") or nil,
				lines=rows,actions={{caption=mine and "Entered" or "Enter",primary=reason==nil or nil,disabled=reason~=nil,reason=reason,
					name="ContestEnter"..id,fn=function() send("contestEnter",id) end}}})
		end
	else
		card({name="ContestNow",icon=CTP.medallion(CT.COLOR,"🌾"),accent=rgb(CT.COLOR),title=paint("HARVEST CONTEST",CT.COLOR),
			subtitle="Three contests every isle day  ·  20 minutes each",badge=paint("BETWEEN BELLS","B9C7CC"),
			detail="Enter one featured crop: everything you harvest of it, in the fields or your Verdant Garden, counts against every isle's farmers.",
			lines={"Next: "..(function() local n={} for _,id in ipairs(at.nextWindow.crops) do table.insert(n,paint(escape(itemName(id)),itemHex(id))) end return table.concat(n,"  ·  ") end)()},
			after=CTP.timer(function(t) return "Next contest in "..CT.span(at.nextWindow.starts-t) end,mint)})
	end
	if at.active then
		local nx={}
		for _,id in ipairs(at.nextWindow.crops) do table.insert(nx,paint(escape(itemName(id)),itemHex(id))) end
		card({name="ContestNext",motif="Workshop",title="Next contest",titleColor=gold,lines={table.concat(nx,"  ·  ")},
			after=CTP.timer(function(t) return "Opens in "..CT.span(at.nextWindow.starts-t) end,muted)})
	end
	if num(s.pending,0)>0 then
		card({name="ContestPending",motif="Ledger",title="Awaiting results",titleColor=gold,
			detail=fmt(s.pending).." finished entr"..(num(s.pending,0)==1 and "y is" or "ies are").." being sealed across the isles. Medals arrive automatically."})
	end
	heading("BRACKETS    /    BY RANK AMONG PLACING ENTRANTS")
	local lines={}
	for _,b in ipairs(CT.Brackets) do
		table.insert(lines,paint(b.name,b.color).."  top "..math.floor(b.top*100+.5).."%  ·  "..b.medals.." medal"..(b.medals==1 and "" or "s").."  ·  needs "..b.minPop.."+ entrants")
	end
	card({name="ContestBrackets",motif="Journal",title="How brackets are awarded",titleColor=gold,lines=lines})
end
local function drawExchange(CT,s)
	local medals=num(s.medals,0)
	local volumes=num(s.almanac,0)
	card({name="ContestMedals",icon=CTP.medallion("F7C548","✪"),title=paint(fmt(medals).." Harvest Medals","F7C548"),
		subtitle=fmt(num(s.earned,0)).." earned in all  ·  Furrow Almanac "..volumes.."/"..#CT.ALMANAC,
		detail="Medals come only from contest brackets. Spend them here; the Exchange never takes coins."})
	heading("MEDAL EXCHANGE")
	local owned=tbl(s.titles)
	for _,e in ipairs(CT.Shop) do
		local cost=CT.offerCost(e,volumes)
		local title,subtitle,lines,itemId,done
		if e.kind=="almanac" then
			itemId=nil
			done=cost==nil
			title="Furrow Almanac"..(done and "" or ("  ·  Vol. "..numeral(volumes+1)))
			subtitle=done and "Complete" or ("+"..CT.ALMANAC[volumes+1].." Farming Fortune, permanent")
			lines={"Volumes read: "..volumes.."/"..#CT.ALMANAC}
		elseif e.kind=="title" then
			local t=CT.TitleById[e.title]
			done=owned[e.title]==true
			title="Title: "..paint(escape(t.title),t.color)
			subtitle="Cosmetic  ·  worn from Records"
			lines={}
		else
			itemId=e.item
			local def=itemDef(e.item)
			done=e.unique and count("items",e.item)>0
			-- QC M1: a base you already upgraded is never offered again.
			if e.unique and not done and CT.upgradesOf then
				for _,up in ipairs(CT.upgradesOf(e.item)) do if count("items",up)>0 then done=true end end
			end
			title=escape(itemName(e.item))..(e.amount>1 and ("  ×"..e.amount) or "")
			subtitle=escape(def and def.description or "")
			lines={e.upgrade and ("Upgrades your "..escape(itemName(e.upgrade))) or "",e.level and ("Requires Farming "..e.level) or "",
				e.gardenLevel and ("Requires garden level "..e.gardenLevel) or ""}
		end
		local reason=(done and "Already yours.") or (cost and medals<cost and ("Needs "..fmt(cost).." Harvest Medals.")) or nil
		card({name="ContestShop"..e.id,item=itemId,motif=itemId==nil and "Ledger" or nil,title=title,titleColor=itemId and rgb(itemHex(itemId)) or gold,subtitle=subtitle,
			badge=done and "OWNED" or (cost and (fmt(cost).." ✪")) or nil,badgeColor=done and mint or gold,lines=lines,
			actions=not done and {{caption="Buy",primary=reason==nil or nil,disabled=reason~=nil,reason=reason,name="ContestBuy"..e.id,fn=function() send("contestBuy",e.id) end}} or nil})
	end
end
local function drawRecords(CT,s)
	local bl={}
	for _,b in ipairs(CT.Brackets) do table.insert(bl,paint(b.name,b.color).." "..fmt(num(tbl(s.brackets)[b.id],0))) end
	card({name="ContestRecord",motif="Journal",title="Your contest record",titleColor=gold,
		subtitle=fmt(num(s.entries,0)).." entries  ·  "..fmt(num(s.placed,0)).." placed",lines={table.concat(bl,"   ")}})
	heading("PERSONAL BESTS")
	for _,c in ipairs(CT.Crops) do
		local best=num(tbl(s.best)[c.id],0)
		card({name="ContestBest"..c.id,item=c.id,title=escape(itemName(c.id)),titleColor=rgb(itemHex(c.id)),
			subtitle=best>0 and ("Best: "..fmt(best)) or "No entry yet",lines={"Places from "..fmt(c.min)}})
	end
	heading("TITLES")
	local any=false
	for _,t in ipairs(CT.Titles) do
		if tbl(s.titles)[t.id] then
			any=true
			local worn=s.title==t.id
			card({name="ContestTitle"..t.id,motif="Ledger",title=paint(escape(t.title),t.color),subtitle=worn and "Worn" or "Unlocked",
				actions={worn and {caption="Hide",name="ContestTitleOff"..t.id,fn=function() send("contestTitle","none") end}
					or {caption="Wear",primary=true,name="ContestTitleWear"..t.id,fn=function() send("contestTitle",t.id) end}}})
		end
	end
	if not any then card({name="ContestTitlesNone",motif="Ledger",title="No titles yet",titleColor=muted,detail="Unlock titles at the Medal Exchange."}) end
	heading("RECENT RESULTS")
	local hist=tbl(s.history)
	if #hist==0 then card({name="ContestHistoryNone",motif="Journal",title="No results yet",titleColor=muted,detail="Finished contests appear here once they are sealed."}) end
	for i,h in ipairs(hist) do
		if type(h)=="table" then
			card({name="ContestHistory"..i,item=h.c,title=escape(itemName(h.c)).."  ·  "..fmt(num(h.s,0)),titleColor=rgb(itemHex(h.c)),
				subtitle="Contest #"..fmt(num(h.k,0)),badge=CTP.bracketText(h.b),badgeColor=gold,
				lines={num(h.m,0)>0 and ("+"..fmt(h.m).." Harvest Medals") or ""}})
		end
	end
end
function CTP.draw()
	table.clear(CTP.timers)
	CTP.boundary=math.huge
	local CT=CD()
	if not CT then dataMissing() return end
	local s=tbl(state.contests)
	local sections={"Contest","Exchange","Records"}
	if not table.find(sections,CTP.section) then CTP.section="Contest" end
	sectionBar(sections,CTP.section,function(name) CTP.section=name;scroll.CanvasPosition=Vector2.zero;render() end,{small=true,prefix="Contests"})
	if CTP.section=="Exchange" then drawExchange(CT,s) elseif CTP.section=="Records" then drawRecords(CT,s) else drawContest(CT,s) end
end
Pages.drawContests=CTP.draw

-- Hunt › Trophies ----------------------------------------------------------------------
local REASON={water="other waters",fishing="Fishing level",rod="rod tier",season="season",event="festival",hours="hour",bait="bait"}
function CTP.conditions(TF,f)
	local parts={paint(escape(TF.WaterById[f.water] and TF.WaterById[f.water].name or f.water),TF.WaterById[f.water] and TF.WaterById[f.water].color or "8FB8D6")}
	table.insert(parts,"Fishing "..f.fishing)
	table.insert(parts,"rod tier "..f.rod.."+")
	if f.hours then table.insert(parts,"isle hours "..f.hours[1].."–"..f.hours[2]) end
	if f.season then table.insert(parts,escape(f.season)) end
	if f.event then local ev=Data.Events and Data.Events[f.event] table.insert(parts,escape(ev and ev.name or f.event)) end
	if f.bait then table.insert(parts,escape(itemName(f.bait))) end
	return table.concat(parts,"  ·  ")
end
local function drawLedger(TF,t)
	local best=tbl(t.best)
	local hour=num(t.hour,12)
	local tiers={}
	for _,tier in ipairs(TF.Tiers) do table.insert(tiers,paint(tier.name,tier.color).." "..TF.countAt(best,tier.id).."/"..#TF.Fish) end
	local bait=type(t.bait)=="string" and TF.Baits[t.bait] and t.bait or nil
	card({name="TrophySummary",icon=CTP.medallion(TF.COLOR,"🏆"),accent=rgb(TF.COLOR),title=paint("TROPHY LEDGER",TF.COLOR),
		subtitle=fmt(num(t.total,0)).." trophy fish  ·  "..fmt(num(t.diamonds,0)).." Diamond  ·  "..fmt(num(t.casts,0)).." casts in trophy waters",
		detail="Any cast in trophy waters that raises no sea creature may land a trophy fish when its conditions are right.",
		lines={table.concat(tiers,"   "),
			"Now: isle hour "..math.floor(hour).."  ·  "..escape(tostring(t.season or "?"))..(type(t.event)=="string" and ("  ·  "..paint(escape(Data.Events and Data.Events[t.event] and Data.Events[t.event].name or t.event),"F7C548")) or "")
				.."  ·  bait: "..(bait and (escape(itemName(bait)).." ("..fmt(num(t.baitHave,0))..")") or "none")}})
	for _,w in ipairs(TF.Waters) do
		heading(string.upper(w.name))
		for _,f in ipairs(TF.Fish) do
			if f.water==w.id then
				local row=tbl(tbl(t.caught)[f.id])
				local got={}
				for _,tier in ipairs(TF.Tiers) do
					local n=num(row[tier.id],0)
					table.insert(got,paint(tier.name:sub(1,1),n>0 and tier.color or "4A5560").." "..fmt(n))
				end
				local b=TF.TierById[best[f.id]]
				local pity=tbl(tbl(t.pity)[f.id])
				local now=f.hours and (TF.inHours(f.hours,hour) and paint("biting hour","9EE7D2") or paint("not its hour","B9C7CC")) or ""
				card({name="Trophy"..f.id,icon=CTP.medallion(f.color,b and "🐟" or "?"),accent=b and rgb(b.color) or nil,title=escape(f.name),titleColor=rgb(f.color),
					subtitle=escape(f.rarity).."  ·  +"..fmt(TF.xp(f,"Bronze")).." Fishing XP (Bronze)",badge=b and string.upper(b.name) or "UNCAUGHT",badgeColor=b and rgb(b.color) or muted,
					detail=escape(f.text),lines={CTP.conditions(TF,f),table.concat(got,"   ")..(now~="" and ("   "..now) or ""),
						"Gold within "..fmt(math.max(0,TF.PITY_GOLD-num(pity.g,0))).."  ·  Diamond within "..fmt(math.max(0,TF.PITY_DIAMOND-num(pity.d,0))).." catches"}})
			end
		end
	end
end
local function drawRewards(TF,t)
	local claimed=tbl(t.claimed)
	for _,l in ipairs(TF.Ledger) do
		local have=TF.countAt(t.best,l.need.tier)
		local need=TF.ledgerNeed(l)
		local done=have>=need
		local got=claimed[l.id]==true
		local parts={}
		if l.title then table.insert(parts,"title "..paint(escape(l.title),l.color)) end
		if l.item then table.insert(parts,escape(itemName(l.item))) end
		if l.xp then table.insert(parts,fmt(l.xp).." Fishing XP") end
		local reason=(got and "Already claimed.") or (not done and ("Catch "..need.." trophy fish at "..l.need.tier.." or better.")) or nil
		local acts={{caption=got and "Claimed" or "Claim",primary=reason==nil or nil,disabled=reason~=nil,reason=reason,name="TrophyClaim"..l.id,fn=function() send("trophyClaim",l.id) end}}
		if got and l.title then
			if t.title==l.id then table.insert(acts,{caption="Hide",name="TrophyTitleOff"..l.id,fn=function() send("trophyTitle","none") end})
			else table.insert(acts,{caption="Wear",name="TrophyTitleWear"..l.id,fn=function() send("trophyTitle",l.id) end}) end
		end
		card({name="TrophyLedger"..l.id,item=l.item,icon=l.item==nil and CTP.medallion(l.color,"✦") or nil,accent=rgb(l.color),title=escape(l.name),titleColor=rgb(l.color),
			subtitle=fmt(math.min(have,need)).."/"..fmt(need).." fish at "..l.need.tier.." or better",badge=got and "CLAIMED" or (done and "READY" or nil),badgeColor=got and muted or mint,
			lines={"Reward: "..table.concat(parts,", ")},bar={fraction=math.clamp(have/math.max(1,need),0,1),color=rgb(l.color),caption=fmt(math.min(have,need)).." / "..fmt(need)},actions=acts})
	end
end
local function drawBait(TF,t)
	local loaded=type(t.bait)=="string" and t.bait or nil
	local cook=skillsOf(state).Cooking
	for _,id in ipairs(TF.BaitOrder) do
		local b=TF.Baits[id]
		local have=count("items",id)
		local mine=loaded==id
		local reason=(have<=0 and ("Cook "..b.name.." at a Hearth (Cooking "..b.level..").")) or nil
		local needs={}
		for cid,n in pairs(b.costs) do table.insert(needs,fmt(n).." "..escape(itemName(cid))) end
		table.sort(needs)
		card({name="TrophyBait"..id,item=id,title=escape(b.name),titleColor=rgb(itemHex(id)),subtitle="+"..UI.dec(b.bonus*100).."% trophy chance  ·  "..fmt(have).." in satchel",
			badge=mine and "LOADED" or nil,badgeColor=mint,
			lines={((cook and cook.level or 1)>=b.level and check or cross).." Cooking "..b.level.."  ·  "..b.amount.." from "..table.concat(needs,", ")},
			actions={mine and {caption="Unload",name="TrophyBaitOff",fn=function() send("trophyBait","none") end}
				or {caption="Load",primary=reason==nil or nil,disabled=reason~=nil,reason=reason,name="TrophyBaitLoad"..id,fn=function() send("trophyBait",id) end}}})
	end
end
function CTP.drawTrophies()
	local TF=TD()
	if not TF then dataMissing() return end
	local t=tbl(state.trophies)
	local sections={"Ledger","Rewards","Bait"}
	if not table.find(sections,CTP.tsection) then CTP.tsection="Ledger" end
	sectionBar(sections,CTP.tsection,function(name) CTP.tsection=name;scroll.CanvasPosition=Vector2.zero;render() end,{small=true,prefix="Trophies"})
	if CTP.tsection=="Rewards" then drawRewards(TF,t) elseif CTP.tsection=="Bait" then drawBait(TF,t) else drawLedger(TF,t) end
end
Pages.drawTrophies=CTP.drawTrophies

-- Countdowns tick in place; the page redraws at the bell.
task.spawn(function()
	while task.wait(1) do
		if #CTP.timers>0 and atlas.Visible and current=="Workshop" and sectionOf and sectionOf.Workshop=="Contests" then
			local now=CTP.now()
			if now>=CTP.boundary then render() else
				for _,t in ipairs(CTP.timers) do pcall(function() t.label.Text=t.fn(now) end) end
			end
		end
	end
end)

-- Contest tracker (right column, during a contest): crop, count, estimate, timer.
local hudFrame=make("TextButton",gui,{Name="ContestHud",Text="",AutoButtonColor=false,BackgroundColor3=deep,BackgroundTransparency=.06,BorderSizePixel=0,
	AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-10,0,240),Size=UDim2.fromOffset(214,64),Visible=false,Selectable=false})
rounded(hudFrame,12,UI.brass)
local hudTitle=label(hudFrame,"",12,4,UDim.new(1,-24),16,UI.heavy,11,gold)
hudTitle.Name="Title"
local hudBody=label(hudFrame,"",12,20,UDim.new(1,-24),18,bold,12,ivory)
hudBody.Name="Lines"
hudBody.RichText=true
hudBody.TextWrapped=true
hudBody.TextYAlignment=Enum.TextYAlignment.Top
hudBody.TextTruncate=Enum.TextTruncate.None
hudFrame.Activated:Connect(function() if Pages.openTo then Pages.openTo("Workshop","Contests") end end)
CTP.hud=hudFrame
function CTP.hudLines(short)
	local CT=CD()
	if not CT then return nil end
	local at,s,entry,now=CTP.contest()
	if not at.active then return nil end
	local lines={}
	local left=CT.span(at.ends-now)
	if entry then
		local est=type(s.estimate)=="table" and s.estimate or nil
		if short then
			table.insert(lines,paint(escape(itemName(entry.c)),itemHex(entry.c)).." "..fmt(num(entry.s,0)))
			table.insert(lines,(est and CTP.bracketText(est.bracket) or paint("…","B9C7CC")).."  "..paint(left,"A9BDC1"))
		else
			table.insert(lines,paint(escape(itemName(entry.c)),itemHex(entry.c)).."  ·  "..paint(fmt(num(entry.s,0)),"FFF4D9").." harvested")
			table.insert(lines,"Estimate: "..(est and CTP.bracketText(est.bracket) or paint("gathering…","B9C7CC")).."   "..paint(left.." left","A9BDC1"))
		end
	else
		local names={}
		for _,id in ipairs(at.crops) do table.insert(names,escape(itemName(id))) end
		table.insert(lines,short and paint(left,"A9BDC1") or (table.concat(names,"  ·  ")))
		if not short then table.insert(lines,paint(left.." left  ·  harvest one to enter","A9BDC1")) end
	end
	return lines
end
function CTP.refreshHud()
	local busy=player:GetAttribute("MinigameGame") or player:GetAttribute("LairBoss")
	local lines=(not busy or busy=="") and CTP.hudLines(false) or nil
	hudFrame.Visible=lines~=nil
	if not lines then return end
	local view=gui.AbsoluteSize
	local height=(view and view.Y>0) and view.Y or 720
	local short=height<520
	lines=CTP.hudLines(short) or lines
	local width=short and 100 or 214
	local lanes=UI.lay()
	local pad=short and 6 or 12
	local titleHeight=short and 14 or 16
	local rowHeight=short and 14 or 18
	local frameHeight=4+titleHeight+rowHeight*#lines+8
	-- QC M3: the right column is shared. Stack under the world boss board
	-- (combat.client.lua publishes its foot as the local attribute
	-- WorldBossBoard) and the dungeon party HUD; hide when there is no room
	-- above the action bar or the stack would meet the XP lane.
	local top=lanes.rightTop
	local boardFoot=num(player:GetAttribute("WorldBossBoard"),0)
	if boardFoot>0 then top=math.max(top,boardFoot+6) end
	local party=gui:FindFirstChild("DungeonPartyHud")
	if party and party.Visible then top=math.max(top,party.Position.Y.Offset+party.Size.Y.Offset+6) end
	local x0=lanes.rightEdge-width
	local function clash(r)
		return type(r)=="table" and num(r.w,0)>0 and num(r.h,0)>0 and r.x<lanes.rightEdge and x0<r.x+r.w and r.y<top+frameHeight and top<r.y+r.h
	end
	if top>lanes.rightTop and (top+frameHeight>lanes.action.y-6 or clash(lanes.xpDrops) or clash(lanes.xpToast)) then
		hudFrame.Visible=false
		return
	end
	hudTitle.Text=short and "CONTEST" or "HARVEST CONTEST"
	hudTitle.Position,hudTitle.Size=UDim2.fromOffset(pad,4),UDim2.new(1,-2*pad,0,titleHeight)
	hudBody.Text=table.concat(lines,"\n")
	hudBody.TextSize=short and 11 or 12
	hudBody.Position=UDim2.fromOffset(pad,4+titleHeight)
	hudBody.Size=UDim2.new(1,-2*pad,0,rowHeight*#lines)
	hudFrame.AnchorPoint=Vector2.new(1,0)
	hudFrame.Position=UDim2.new(0,lanes.rightEdge,0,top)
	hudFrame.Size=UDim2.fromOffset(width,frameHeight)
end
for _,name in ipairs({"MinigameGame","LairBoss","IsleSatchelOpen","WorldBossBoard","DungeonParty"}) do
	player:GetAttributeChangedSignal(name):Connect(function() CTP.refreshHud() end)
end
task.spawn(function()
	while task.wait(1) do pcall(CTP.refreshHud) end
end)
end
------------------------------------------------------------------------------
-- Exploration & Factions (Exploration & Factions team). Journal › Motes
-- (found counter, milestones, Wayglass bearing, per-region progress) and
-- Journal › Factions (pledge, reputation ranks, daily tasks, shop, titles).
-- Server state: snapshot.exploration = {rev, motes, factions} (Explore.state)
-- when it changed, else {rev, resetIn, switchIn, compact = true}; EXP.data()
-- keeps the last full copy and asks "exploreSync" on a cache miss. Board
-- entries carry {id, progress, claimed}: done, reward and items held are
-- derived here (FA.reward, snapshot.items).
-- Verbs: moteHint, factionPledge "<id>", factionClaim "<id>:<slot>|all",
-- factionDeliver "<id>:<slot>", factionBuy "<shop>[:<skill>]",
-- factionTitle "<shop>|none", exploreSync. The world motes are drawn by
-- motes.client.lua, which asks this page's sender (IsleActionLocal "moteCollect") to pick up.
------------------------------------------------------------------------------
do
local EXP={cache=nil,asked=nil,askedAt=0}
-- Every accepted snapshot passes here: a full exploration replaces the cache;
-- a compact one refreshes the timers of the matching cached revision.
function EXP.observe(data)
	local ex=type(data)=="table" and data.exploration
	if type(ex)~="table" then return end
	if ex.compact then
		local cached=EXP.cache
		if cached and cached.rev==ex.rev and type(cached.factions)=="table" then
			cached.factions.resetIn=ex.resetIn
			cached.factions.switchIn=ex.switchIn
		end
	elseif type(ex.motes)=="table" then
		EXP.cache=ex
	end
end
-- The exploration state to draw (nil = not synced yet).
function EXP.data()
	local ex=state and state.exploration
	if type(ex)~="table" then return nil end
	if not ex.compact then EXP.observe(state) return ex end
	local cached=EXP.cache
	if cached and cached.rev==ex.rev then return cached end
	if send and (EXP.asked~=ex.rev or os.clock()-EXP.askedAt>3) then
		EXP.asked,EXP.askedAt=ex.rev,os.clock()
		task.defer(function() send("exploreSync",nil,true) end)
	end
	return cached -- an older copy while the fresh one is on its way
end
-- A board entry with its derived fields.
function EXP.slot(s,t,pledge)
	local items=tbl(state and state.items)
	return {done=num(s.progress,0)>=t.amount,reward=Data.Factions.reward(t,pledge),have=if t.kind=="deliver" then num(items[t.target],0) else nil}
end
Pages.EXP=EXP
function EXP.ready() return Data and type(Data.Exploration)=="table" and type(Data.Factions)=="table" end
function EXP.clock(seconds)
	seconds=math.max(0,math.floor(num(seconds,0)))
	if seconds>=86400 then return string.format("%dd %dh",seconds//86400,(seconds%86400)//3600) end
	return string.format("%dh %02dm",seconds//3600,(seconds%3600)//60)
end
function EXP.statText(stats)
	local parts={}
	for stat,v in pairs(tbl(stats)) do table.insert(parts,"+"..fmt(v).." "..(Data.Stats[stat] and Data.Stats[stat].name or stat)) end
	table.sort(parts)
	return table.concat(parts,", ")
end
function EXP.drawMotes()
	if not EXP.ready() then dataMissing() return end
	local EX=Data.Exploration
	local ex=tbl(EXP.data())
	local m=tbl(ex.motes)
	local synced=type(ex.motes)=="table"
	local found=tostring(m.found or "")
	local count=num(m.count,0)
	local claimable=num(m.claimable,0)
	local steps=num(m.steps,0)
	local cost=num(m.hintCost,EX.hintCost(count))
	local perks=EXP.statText(m.stats)
	card({name="MotesSummary",motif="Journal",accent=rgb(EX.MOTE.color),title=EX.MOTE.plural,titleColor=gold,
		subtitle=paint(EX.MOTE.symbol.." "..fmt(count).." / "..fmt(EX.TOTAL),EX.MOTE.color).." found   ·   "..steps.." / "..EX.STEPS.." milestones claimed",
		badge=synced and (claimable>0 and (claimable.." READY") or "SEEKING") or "SYNCING",badgeColor=claimable>0 and mint or gold,
		detail="Tiny drifting motes hide on every island: on rooftops and ledges, under trees, beside landmarks and high on the Agility course perches. Walk up to one and gather it. Every "
			..EX.STEP.." found is a milestone you claim at any Mote Shrine for permanent stats.",
		bar={fraction=count/math.max(1,EX.TOTAL),color=rgb(EX.MOTE.color),caption=fmt(count).." / "..fmt(EX.TOTAL)},
		lines={perks~="" and ("Mote perks: "..perks) or "No mote perks yet.",
			claimable>0 and paint(claimable.." milestone"..(claimable==1 and "" or "s").." ready: visit any Mote Shrine.","8EE6CB") or nil},
		actions={{caption="Wayglass · "..fmt(cost).." coins",name="MoteHint",primary=num(state and state.coins,0)>=cost,disabled=num(state and state.coins,0)<cost or not synced,
			reason="A Wayglass bearing costs "..fmt(cost).." coins.",fn=function() send("moteHint") end}}})
	local hintId=type(m.hint)=="string" and m.hint or nil
	local hinted=hintId and EX.MoteById[hintId]
	if hinted then
		card({name="MoteBearing",motif="Journal",accent=rgb(EX.MOTE.color),title="Wayglass bearing",titleColor=rgb(EX.MOTE.color),
			subtitle=escape(hinted.hint),badge="ACTIVE",badgeColor=mint,
			detail="A beacon marks the mote in the world until you gather it or the bearing fades."})
	end
	heading("MILESTONES    /    EVERY "..EX.STEP.." MOTES")
	local nextAt=(steps+1)*EX.STEP
	-- The totals after the next milestone include the regions already claimed (QC L9).
	local claimedRegions=0
	for _,r in pairs(tbl(m.regions)) do if type(r)=="table" and r.claimed then claimedRegions+=1 end end
	local nextStats=EXP.statText(EX.perkStats(steps+1,claimedRegions))
	card({name="MoteMilestones",motif="Hero",title="Shrine milestones",titleColor=gold,
		subtitle=steps<EX.STEPS and ("Next at "..nextAt.." motes: +"..fmt(EX.stepCoins(steps+1)).." coins") or "Every milestone claimed",
		detail="Each claimed milestone adds +2 Health; every second one also adds +1 Defense and +1 Speed. Completing a whole region pays a bonus at that region's own shrine (+"
			..EX.REGION_HEALTH.." Health and coins).",
		lines={steps<EX.STEPS and ("After the next milestone: "..nextStats) or nil},
		pips={total=EX.STEPS,filled=steps,color=mint}})
	heading("REGIONS")
	local regions=tbl(m.regions)
	for _,region in ipairs(EX.RegionOrder) do
		local r=tbl(regions[region])
		local def=Data.RegionById[region]
		local total=EX.RegionTotal[region]
		local here,gated=0,0
		local lines={}
		for _,id in ipairs(EX.MotesByRegion[region]) do
			local mote=EX.MoteById[id]
			local got=string.sub(found,mote.index,mote.index)=="1"
			if got then here+=1; table.insert(lines,check.." "..escape(mote.hint))
			elseif mote.agility>num(m.agility,1) then gated+=1 end
		end
		if gated>0 then table.insert(lines,paint(gated.." more drift over Agility courses you cannot run yet.","F3C66E")) end
		local allowed=r.allowed~=false
		card({name="MoteRegion"..region,motif="Journal",accent=rgb(EX.MOTE.color),title=escape(def and def.name or region),titleColor=ivory,
			subtitle=here.." / "..total.." found",badge=r.claimed and "COMPLETE" or (not allowed and "LOCKED" or (here>=total and "CLAIM" or "SEEKING")),
			badgeColor=r.claimed and mint or (not allowed and muted or gold),
			bar={fraction=here/math.max(1,total),color=r.claimed and mint or rgb(EX.MOTE.color),caption=here.." / "..total},
			lines=lines})
	end
end
-- Factions --------------------------------------------------------------------
function EXP.taskText(t)
	if t.kind=="kill" then return "Defeat "..t.amount.." "..escape(Data.Monsters[t.target] and Data.Monsters[t.target].name or t.target) end
	if t.kind=="gather" then return "Harvest "..t.amount.." "..escape(itemName(t.target)) end
	return "Deliver "..t.amount.." "..escape(itemName(t.target))
end
function EXP.drawFactions()
	if not EXP.ready() then dataMissing() return end
	local FA=Data.Factions
	local ex=tbl(EXP.data())
	local fs=tbl(ex.factions)
	local synced=type(ex.factions)=="table"
	local list=tbl(fs.list)
	local pledge=type(fs.pledge)=="string" and FA.Factions[fs.pledge] or nil
	local ready=0
	for _,id in ipairs(FA.Order) do
		for _,s in ipairs(tbl(tbl(list[id]).board)) do
			local t=FA.TaskById[s.id]
			if t and t.kind~="deliver" and num(s.progress,0)>=t.amount and not s.claimed then ready+=1 end
		end
	end
	card({name="FactionsSummary",motif="Journal",accent=pledge and rgb(pledge.color) or gold,title="Factions",titleColor=gold,
		subtitle=pledge and ("Pledged to the "..paint(pledge.name,pledge.color)) or "Unpledged",
		badge=synced and ("RESETS "..EXP.clock(fs.resetIn)) or "SYNCING",badgeColor=mint,
		detail="Three orders vie for the isles. Each posts three tasks a day (UTC). Pledging to one earns full reputation and sigils with it, a quarter with its rival and 60% with the third; unpledged journals earn 60% everywhere. Rewards above Kindred need the pledge. Changing a pledge costs "
			..fmt(FA.SWITCH_COST).." coins, a quarter of the old reputation and waits "..(FA.SWITCH_COOLDOWN//86400).." days after the last pledge.",
		lines={fs.titleText and fs.titleText~="" and ("Title: "..escape(fs.titleText)) or nil,
			pledge and num(fs.switchIn,0)>0 and ("Pledge can change in "..EXP.clock(fs.switchIn)..".") or nil},
		actions=ready>0 and {{caption="Claim all",name="FactionClaimAll",primary=true,fn=function() send("factionClaim","all") end}} or nil})
	for _,id in ipairs(FA.Order) do
		local def=FA.Factions[id]
		local f=tbl(list[id])
		local rep=num(f.rep,0)
		local index=num(f.rank,1)
		local rank=FA.Ranks[index] or FA.Ranks[1]
		local nextRank=FA.Ranks[index+1]
		local floor=rank.at
		local frac=nextRank and (rep-floor)/math.max(1,nextRank.at-floor) or 1
		local actions={}
		if synced and fs.pledge~=id then
			local switching=pledge~=nil
			local wait=switching and num(fs.switchIn,0) or 0
			local afford=not switching or num(state and state.coins,0)>=FA.SWITCH_COST
			table.insert(actions,{caption=switching and ("Switch · "..fmt(FA.SWITCH_COST)) or "Pledge",name="FactionPledge"..id,primary=not switching and true or false,
				disabled=wait>0 or not afford,reason=wait>0 and ("Your pledge holds for "..EXP.clock(wait)..".") or ("Changing a pledge costs "..fmt(FA.SWITCH_COST).." coins."),
				fn=function() send("factionPledge",id) end})
		end
		heading(string.upper(def.name).."    /    "..string.upper(rank.name))
		card({name="Faction"..id,motif="Hero",accent=rgb(def.color),title=escape(def.name),titleColor=rgb(def.color),
			subtitle=escape(rank.name).."   ·   "..fmt(rep).." reputation   ·   "..fmt(num(f.sigils,0)).." sigils",
			badge=fs.pledge==id and "PLEDGED" or (pledge and pledge.rival==id and "RIVAL" or "x"..tostring(num(f.mult,0.6))),
			badgeColor=fs.pledge==id and mint or (pledge and pledge.rival==id and rgb("E8806A") or gold),
			detail="\""..escape(def.motto).."\" "..escape(def.text),
			bar={fraction=math.clamp(frac,0,1),color=rgb(def.color),caption=nextRank and (fmt(rep).." / "..fmt(nextRank.at).." to "..nextRank.name) or "Highest rank"},
			actions=#actions>0 and actions or nil})
		for i,s in ipairs(tbl(f.board)) do
			local t=FA.TaskById[s.id]
			if t then
				local d=EXP.slot(s,t,fs.pledge)
				local r=d.reward
				local progress=math.min(num(s.progress,0),t.amount)
				local acts={}
				if t.kind=="deliver" and not s.claimed then
					local have=num(d.have,0)
					table.insert(acts,{caption="Deliver",name="FactionDeliver"..id..i,primary=have>=t.amount,disabled=have<t.amount,
						reason="You have "..fmt(have).." of "..t.amount..".",fn=function() send("factionDeliver",id..":"..i) end})
				elseif d.done and not s.claimed then
					table.insert(acts,{caption="Claim",name="FactionClaim"..id..i,primary=true,fn=function() send("factionClaim",id..":"..i) end})
				end
				card({name="FactionTask"..id..i,item=(t.kind~="kill" and t.target) or nil,motif=t.kind=="kill" and "Hunt" or nil,accent=rgb(def.color),
					title=EXP.taskText(t),titleColor=ivory,subtitle=def.short.."   ·   "..t.kind,
					badge=s.claimed and "DONE" or (d.done and "READY" or "ACTIVE"),badgeColor=s.claimed and muted or (d.done and mint or gold),
					lines={"+"..fmt(num(r.rep,0)).." reputation   ·   +"..fmt(num(r.sigils,0)).." sigils   ·   +"..fmt(num(r.coins,0)).." coins"
						..(num(r.xp,0)>0 and ("   ·   +"..fmt(r.xp).." "..tostring(r.skill).." XP") or "")},
					bar=t.kind~="deliver" and {fraction=progress/math.max(1,t.amount),color=d.done and mint or rgb(def.color),caption=fmt(progress).." / "..fmt(t.amount)} or nil,
					actions=#acts>0 and acts or nil})
			end
		end
	end
	heading("FACTION REWARDS")
	local unlocks={}
	for _,id in ipairs(tbl(fs.unlocks)) do unlocks[id]=true end
	for _,e in ipairs(FA.Shop) do
		local def=FA.Factions[e.faction]
		local f=tbl(list[e.faction])
		local okRank=num(f.rank,1)>=e.rank
		local okPledge=e.rank<=FA.OPEN_RANK or fs.pledge==e.faction
		local okSigils=num(f.sigils,0)>=e.sigils
		local okCoins=num(state and state.coins,0)>=(e.coins or 0)
		local can=synced and okRank and okPledge and okSigils and okCoins
		local why=not okRank and ("Needs "..FA.Ranks[e.rank].name.." standing.") or (not okPledge and ("Pledge to the "..def.name.." first.")) or (not okSigils and ("Needs "..e.sigils.." sigils.")) or ("Needs "..fmt(e.coins or 0).." coins.")
		local title,subtitle,acts
		if e.kind=="title" then
			title="Title: "..e.title
			if unlocks[e.id] then
				acts={fs.title==e.id and {caption="Hide",name="FactionTitleOff"..e.id,fn=function() send("factionTitle","none") end}
					or {caption="Wear",name="FactionTitle"..e.id,primary=true,fn=function() send("factionTitle",e.id) end}}
			else
				acts={{caption="Earn",name="FactionBuy"..e.id,primary=can,disabled=not can,reason=why,fn=function() send("factionBuy",e.id) end}}
			end
		elseif e.kind=="lamp" then
			title=def.short.." lamp"
			acts={}
			for _,skill in ipairs(def.lampSkills) do
				table.insert(acts,{caption=skill,name="FactionBuy"..e.id..skill,primary=can,disabled=not can,reason=why,fn=function() send("factionBuy",e.id..":"..skill) end})
			end
		else
			title=itemName(e.item)
			acts={{caption=e.kind=="crest" and "Reforge" or "Buy",name="FactionBuy"..e.id,primary=can,disabled=not can,reason=why,fn=function() send("factionBuy",e.id) end}}
		end
		subtitle=FA.Ranks[e.rank].name.."   ·   "..e.sigils.." sigils"..((e.coins or 0)>0 and ("   ·   "..fmt(e.coins).." coins") or "")
		local detail
		if e.kind=="lamp" then detail="XP in "..table.concat(def.lampSkills,", ").." (about "..math.floor(FA.LAMP_HOURS*60).." minutes of level-appropriate training). Repeatable."
		elseif e.kind=="title" then detail="A cosmetic title shown in your journal."
		else local item=itemDef(e.item); detail=item and escape(item.description) or nil end
		card({name="FactionShop"..e.id,item=e.item,motif=if e.item then nil else "Journal",accent=rgb(def.color),title=escape(title),titleColor=rgb(def.color),subtitle=subtitle,
			badge=unlocks[e.id] and "OWNED" or (okRank and okPledge and "OPEN" or "LOCKED"),badgeColor=unlocks[e.id] and mint or (okRank and okPledge and gold or muted),
			detail=detail,actions=acts})
	end
end
Pages.drawMotes,Pages.drawFactions=EXP.drawMotes,EXP.drawFactions
end

------------------------------------------------------------------------------
-- §33 Systems Depth (docs/DEPTH-CONTRACT.md §33): the quest helper (Journal ›
-- Helper, plus Guide / Pin / Waypoint on quest, diary and contract cards), the
-- goal board (Journal › Goals), market price history (Ledger › Prices and the
-- Bazaar book card), the XP calculator (Hero › Calculator) and daily stock
-- text on vendor / Roost offers. Server state: snapshot.systems = {pin, goals,
-- goalMax, rates, window, prices, stock = {resetIn, left = {[key] = {left, limit}}}};
-- verbs helperPin, goalSet, goalRemove, goalClear, priceCheck. Guides are
-- derived on the client from the same pure functions the server uses
-- (Data.Systems.Helper), so the Journal and the pinned sidebar step agree.
------------------------------------------------------------------------------
do
local SYS={open={},goalKind="Level",goalSkill="Mining",calcSkill="Mining",calcTarget=nil,priceGroup="Mining",priceItem="Ore",pricePage=1,
	PRICE_PAGE=48,REFRESH_GAP=10,refreshAt={}}
Pages.SYS=SYS
function SYS.data() return Data and type(Data.Systems)=="table" and Data.Systems or nil end
function SYS.state() return tbl(state.systems) end
function SYS.pinned() return tbl(SYS.state().pin).id end
function SYS.waypoint(specs,label)
	if type(specs)~="table" or #specs==0 then notify("There is no waypoint for this step: follow the text.") return end
	local request=player:FindFirstChild("WayfinderRequest")
	if request then
		request:Fire(specs,label)
		if atlas.Visible then closeAtlas() end
	else
		notify("The Wayfinder is still charting the isles. Try again in a moment.")
	end
end
-- Region access from the snapshot (depth.regions), for waypoints (§33 QC L4).
function SYS.access()
	local d=depth()
	if not d or type(d.regions)~="table" then return nil end
	local access={}
	for _,r in ipairs(d.regions) do if type(r)=="table" and type(r.id)=="string" then access[r.id]=r.unlocked==true end end
	return access
end
-- Client-side guide for a pin id (same derivation as the server's pinned step).
function SYS.guide(id)
	local SY=SYS.data()
	local j=tbl(state.journal)
	if not SY or type(id)~="string" then return nil end
	local HP=SY.Helper
	if id=="contract" then return HP.contractGuide(state.quest) end
	local kind,arg=string.match(id,"^(%a+):(%w+)$")
	if kind=="quest" then
		local q=Data.QuestById[arg]
		if not q then return nil end
		local entry
		for _,e in ipairs(tbl(j.quests)) do if type(e)=="table" and e.id==arg then entry=e end end
		local accepted=tbl(tbl(state.regionQuests).accepted)[arg]==true
		return HP.questGuide(q,entry,{accepted=accepted,access=SYS.access()})
	elseif kind=="diary" then
		local d=Data.DiaryByRegion[arg]
		if not d then return nil end
		local entry=EMPTY
		for _,e in ipairs(tbl(j.diaries)) do if type(e)=="table" and e.region==arg then entry=e end end
		local tierName=HP.diaryTier(num(entry.claimed,0))
		local tier
		for _,t in ipairs(tbl(entry.tiers)) do if type(t)=="table" and t.tier==tierName then tier=t end end
		return HP.diaryGuide(d,tierName,tier,{access=SYS.access()})
	end
	return nil
end
-- " · Unlocks with <region>: …" after a step in a locked region (empty otherwise).
function SYS.blockedText(s)
	return type(tbl(s).blocked)=="string" and paint("  ·  "..escape(s.blocked),"E8806A") or ""
end
-- Checklist rows: done ✓, the current step marked ➤ (gold), have/need counts.
function SYS.steps(body,nextOrder,g)
	local items={}
	for i,s in ipairs(tbl(g.steps)) do
		local text=escape(tostring(s.text))
		if i==g.current and not s.met then text=paint("➤ ","F3C66E")..paint(text,"F3C66E") end
		local npc=s.npc and Data.RegionArt and Data.RegionArt.FolkByRole[s.npc]
		if npc and i==g.current then text..=paint("  ·  "..escape(npc.title or "NPC"),"A9B4C0") end
		if i==g.current and not s.met then text..=SYS.blockedText(s) end
		table.insert(items,{text=text,met=s.met==true,amount=num(s.need,1)>1 and (fmt(num(s.have,0)).." / "..fmt(num(s.need,1))) or nil})
	end
	UI.checklist(body,nextOrder,"STEP BY STEP",items)
end
-- Guide / Pin / Waypoint actions for a guide card (appended to `actions`).
function SYS.actions(id,g,actions,expandable)
	local pinned=SYS.pinned()==id
	local s=g and g.steps[g.current]
	if expandable then
		local open=SYS.open[id]==true
		table.insert(actions,{caption=open and "Hide guide" or "Guide",name="Guide"..id:gsub("[^%w]",""),fn=function() SYS.open[id]=not open render() end})
	end
	if g and g.status~="done" then
		table.insert(actions,{caption=pinned and "Unpin" or "Pin",primary=not pinned,name="Pin"..id:gsub("[^%w]",""),
			fn=function() send("helperPin",pinned and "" or id) end})
		if s and type(s.specs)=="table" and #s.specs>0 then
			table.insert(actions,{caption="Waypoint",name="Waypoint"..id:gsub("[^%w]",""),fn=function() SYS.waypoint(s.specs,escape(tostring(s.text))) end})
		elseif s and type(s.blocked)=="string" then
			-- §33 QC L4: the step lies in a locked region: its requirement, not a waypoint.
			table.insert(actions,{caption="Locked",disabled=true,reason=s.blocked,name="Waypoint"..id:gsub("[^%w]",""),fn=function() notify(s.blocked) end})
		end
	end
	return actions
end
-- Quest cards (Journal › Quests): a NEXT line, Guide / Pin / Waypoint, and the
-- step list when expanded. Returns the `after` drawer (or nil).
function SYS.questExtras(q,entry,actions,lines)
	if not SYS.data() or tbl(entry).done==true then return nil end
	local id="quest:"..q.id
	local g=SYS.guide(id)
	if not g then return nil end
	local s=g.steps[g.current]
	if s then table.insert(lines,1,"<b>"..paint("NEXT  ","9EE7D2").."</b>"..escape(tostring(s.text))..(num(s.need,1)>1 and paint("  "..fmt(num(s.have,0)).."/"..fmt(num(s.need,1)),"A9B4C0") or "")..SYS.blockedText(s)) end
	SYS.actions(id,g,actions,true)
	if SYS.open[id] then return function(body,nextOrder) SYS.steps(body,nextOrder,g) end end
	return nil
end
-- One compact helper card for a diary region or the guild contract.
function SYS.helperCard(id,subtitle)
	local g=SYS.guide(id)
	if not g or g.status=="done" then return end
	local s=g.steps[g.current] or EMPTY
	local open=SYS.open[id]==true
	card({name="Helper"..id:gsub("[^%w]",""),motif="Journal",title=paint("◆ ","9EE7D2")..escape(g.title),subtitle=subtitle,
		badge=SYS.pinned()==id and paint("PINNED","F3C66E") or nil,badgeColor=gold,
		lines={"<b>"..paint("NEXT  ","9EE7D2").."</b>"..escape(tostring(s.text or ""))..SYS.blockedText(s)},
		pips={total=math.max(1,num(g.total,1)),filled=num(g.done,0),color=mint},
		after=open and function(body,nextOrder) SYS.steps(body,nextOrder,g) end or nil,
		actions=SYS.actions(id,g,{},true)})
end
-- Journal › Helper: the pinned guide in full, then everything that can be pinned.
function SYS.drawHelper()
	heading("QUEST HELPER    /    STEP BY STEP")
	if not SYS.data() or type(Data.Quests)~="table" then dataMissing() return end
	local j=state.journal
	if type(j)~="table" then syncing("quest helper") return end
	local pinId=SYS.pinned()
	local pg=pinId and SYS.guide(pinId)
	if pg then
		local s=pg.steps[pg.current] or EMPTY
		card({name="HelperPinned",motif="Journal",edge=gold,title=paint("PINNED  ","F3C66E")..escape(pg.title),
			subtitle="Shown in your sidebar Objective  ·  step "..fmt(num(pg.current,1)).." of "..fmt(num(pg.total,1)),
			detail=escape(tostring(s.text or "")),before=function(body,nextOrder) SYS.steps(body,nextOrder,pg) end,
			actions=SYS.actions(pinId,pg,{},false)})
	else
		card({name="HelperIntro",motif="Journal",title="Pin a quest to your sidebar",
			detail="Every quest, regional quest, diary and guild contract has a guide built from its own requirements: what to do next, what you have and need, and a Wayfinder waypoint to where it happens. Pin one and its current step replaces the Objective in your sidebar."})
	end
	heading("ACTIVE QUESTS")
	local shown=0
	local entries={}
	for _,e in ipairs(tbl(j.quests)) do if type(e)=="table" and type(e.id)=="string" then entries[e.id]=e end end
	local list={}
	for _,q in ipairs(Data.Quests) do
		local e=entries[q.id] or EMPTY
		if e.done~=true and e.available==true then table.insert(list,q) end
	end
	table.sort(list,function(a,b)
		local ra,rb=(entries[a.id] or EMPTY).ready==true,(entries[b.id] or EMPTY).ready==true
		if ra~=rb then return ra end
		return a.index<b.index
	end)
	for _,q in ipairs(list) do
		if shown>=12 then break end
		local id="quest:"..q.id
		local g=SYS.guide(id)
		if g and ("quest:"..q.id)~=pinId then
			local s=g.steps[g.current] or EMPTY
			local region=Data.RegionById and Data.RegionById[q.region]
			card({name="HelperQuest"..q.id,motif="Journal",title=escape(q.title),
				subtitle=escape((region and region.name or tostring(q.region)).."  ·  "..(q.line=="main" and "Main quest" or (q.regional and "Regional quest" or "Side quest"))),
				badge=g.status=="ready" and "READY" or (g.status=="accept" and "ACCEPT" or nil),badgeColor=gold,
				lines={"<b>"..paint("NEXT  ","9EE7D2").."</b>"..escape(tostring(s.text or ""))..(num(s.need,1)>1 and paint("  "..fmt(num(s.have,0)).."/"..fmt(num(s.need,1)),"A9B4C0") or "")..SYS.blockedText(s)},
				pips={total=math.max(1,num(g.total,1)),filled=num(g.done,0),color=mint},
				after=SYS.open[id] and function(body,nextOrder) SYS.steps(body,nextOrder,g) end or nil,
				actions=SYS.actions(id,g,{},true)})
			shown+=1
		end
	end
	if shown==0 then row("Nothing open","Quests appear here once you meet their requirements. Locked quests list them in Journal › Quests.") end
	heading("DIARIES & CONTRACTS")
	if pinId~="contract" then SYS.helperCard("contract","Guild contract  ·  stage "..fmt(num(tbl(state.quest).stage,1)).." of "..fmt(num(tbl(state.quest).total,8))) end
	for _,d in ipairs(Data.Diaries) do
		local id="diary:"..d.region
		if id~=pinId then SYS.helperCard(id,"Achievement diary") end
	end
end

-- Goal board ------------------------------------------------------------------
SYS.goalKinds={Level="level",XP="xp",Collection="tier",Items="item",Quest="quest",Boss="kills"}
SYS.goalOrder={"Level","XP","Collection","Items","Quest","Boss"}
function SYS.setGoal(kind,arg,n) send("goalSet",kind..":"..arg..":"..math.max(1,math.floor(n))) end
function SYS.skills()
	local out={}
	for _,s in ipairs(tbl(Data and Data.SkillOrder)) do table.insert(out,s) end
	return out
end
function SYS.drawGoals()
	local sys=SYS.state()
	local SY=SYS.data()
	local goals=tbl(sys.goals)
	local max=num(sys.goalMax,12)
	heading("GOAL BOARD    /    "..#goals.." OF "..fmt(max))
	if not SY then dataMissing() return end
	if type(state.systems)~="table" then syncing("goal board") return end
	local done=0
	for _,g in ipairs(goals) do if type(g)=="table" and g.done then done+=1 end end
	card({name="GoalSummary",motif="Journal",title="Personal goals",titleColor=gold,
		subtitle=#goals.." set  ·  "..done.." finished  ·  ETAs from your last "..fmt(num(sys.window,1800)//60).." minutes",
		detail="Set targets for skills, collections, items, quests and bosses. Progress is tracked by the server and a toast fires when a goal is reached.",
		actions=done>0 and {{caption="Clear finished",name="GoalClear",fn=function() send("goalClear") end}} or nil})
	for _,g in ipairs(goals) do
		if type(g)=="table" then
			local have,need=num(g.have,0),math.max(1,num(g.need,1))
			local eta
			if g.done then eta=paint("Complete","6FE3C8")
			elseif g.k=="quest" then eta=paint("Follow it in Journal › Helper","A9B4C0")
			else
				local rate=num(g.rate,0)
				eta="ETA "..SY.Goals.etaText(g.eta)..(rate>0 and ("  ·  "..fmt(rate).."/h") or "")
			end
			local caption=g.k=="level" and (fmt(have).." / "..fmt(need).." XP") or (fmt(math.min(have,need)).." / "..fmt(need))
			local acts={{caption="Remove",name="GoalRemove"..tostring(g.id),fn=function() send("goalRemove",tostring(g.id)) end}}
			if g.k=="quest" and not g.done then
				table.insert(acts,1,{caption="Pin",name="GoalPin"..tostring(g.id),fn=function() send("helperPin","quest:"..tostring(g.a)) end})
			end
			card({name="Goal"..tostring(g.id),motif=g.k=="kills" and "Hunt" or (g.k=="tier" or g.k=="item") and "Satchel" or "Hero",
				title=escape(tostring(g.label or "Goal")),titleColor=g.done and mint or ivory,subtitle=eta,
				badge=g.done and paint("DONE","6FE3C8") or nil,badgeColor=mint,
				bar={fraction=math.clamp(have/need,0,1),color=g.done and mint or gold,caption=caption},actions=acts})
		end
	end
	if #goals>=max then row("Board full","Remove a goal to add another.") return end
	heading("ADD A GOAL")
	sectionBar(SYS.goalOrder,SYS.goalKind,function(name) SYS.goalKind=name render() end,{small=true,prefix="GoalKind",maxPer=6})
	local kind=SYS.goalKinds[SYS.goalKind]
	local skills=skillsOf(state)
	if kind=="level" or kind=="xp" then
		local list=SYS.skills()
		if not table.find(list,SYS.goalSkill) then SYS.goalSkill=list[1] or "Mining" end
		sectionBar(list,SYS.goalSkill,function(name) SYS.goalSkill=name render() end,{small=true,prefix="GoalSkill",maxPer=compactAtlas and 4 or 7})
		local skill=SYS.goalSkill
		local info=skills[skill] or EMPTY
		local lvl,xp=num(info.level,1),num(info.xp,num(tbl(state.xp)[skill],0))
		local acts={}
		if kind=="level" then
			for _,step in ipairs({1,5,10}) do
				if lvl+step<=99 then table.insert(acts,{caption="Level "..(lvl+step),name="GoalAddLevel"..step,fn=function() SYS.setGoal("level",skill,lvl+step) end}) end
			end
			if lvl<99 then table.insert(acts,{caption="Level 99",primary=true,name="GoalAddLevel99",fn=function() SYS.setGoal("level",skill,99) end}) end
		else
			for _,step in ipairs({10000,100000,1000000}) do
				local target=math.floor(xp/step+1)*step
				table.insert(acts,{caption=fmt(target).." XP",name="GoalAddXp"..step,fn=function() SYS.setGoal("xp",skill,target) end})
			end
		end
		card({name="GoalAddSkill",motif="Hero",title=escape(skill).."  ·  level "..fmt(lvl),subtitle=fmt(xp).." XP",actions=acts})
	elseif kind=="tier" then
		local list={}
		for _,id in ipairs(tbl(Data.CollectionItems)) do if num(tbl(state.collection)[id],0)>0 then table.insert(list,id) end end
		table.sort(list,function(a,b) return num(tbl(state.collection)[a],0)>num(tbl(state.collection)[b],0) end)
		local function threshold(id,t) return math.max(1,math.floor(Data.CollectionTiers[t]*num(Data.CollectionScale[id],1))) end
		for i=1,math.min(10,#list) do
			local id=list[i]
			local have=num(tbl(state.collection)[id],0)
			local tier=0
			for t=1,#Data.CollectionTiers do
				if have>=threshold(id,t) then tier=t end
			end
			if tier<#Data.CollectionTiers then
				card({name="GoalAddTier"..id,item=id,title=escape(itemName(id)),subtitle="Tier "..tier.."  ·  "..fmt(have).." collected",
					actions={{caption="Tier "..(tier+1),name="GoalTierNext"..id,fn=function() SYS.setGoal("tier",id,tier+1) end},
						{caption="Tier "..#Data.CollectionTiers,name="GoalTierMax"..id,fn=function() SYS.setGoal("tier",id,#Data.CollectionTiers) end}}})
			end
		end
		if #list==0 then row("No collections yet","Gather, fish, farm or fight to start a collection.") end
	elseif kind=="item" then
		local list={}
		for id,n in pairs(tbl(state.items)) do if num(n,0)>0 and itemDef(id) then table.insert(list,id) end end
		table.sort(list,function(a,b) return num(tbl(state.items)[a],0)>num(tbl(state.items)[b],0) end)
		for i=1,math.min(10,#list) do
			local id=list[i]
			local have=num(tbl(state.items)[id],0)
			card({name="GoalAddItem"..id,item=id,title=escape(itemName(id)),subtitle="Holding ×"..fmt(have),
				actions={{caption="+64",name="GoalItem64"..id,fn=function() SYS.setGoal("item",id,have+64) end},
					{caption="+640",name="GoalItem640"..id,fn=function() SYS.setGoal("item",id,have+640) end},
					{caption="×2",name="GoalItemDouble"..id,fn=function() SYS.setGoal("item",id,have*2) end}}})
		end
		if #list==0 then row("Empty satchel","Items you hold appear here.") end
	elseif kind=="quest" then
		local j=tbl(state.journal)
		local shown=0
		for _,e in ipairs(tbl(j.quests)) do
			local q=type(e)=="table" and Data.QuestById[e.id]
			if q and e.done~=true and shown<10 then
				shown+=1
				card({name="GoalAddQuest"..q.id,motif="Journal",title=escape(q.title),subtitle=e.available and "Available" or "Locked: requirements listed in Journal › Quests",
					actions={{caption="Track",name="GoalQuest"..q.id,fn=function() SYS.setGoal("quest",q.id,1) end}}})
			end
		end
		if shown==0 then row("Every quest done","There is no quest left to track.") end
	elseif kind=="kills" then
		local kc=tbl(tbl(state.lairs).kc)
		local best=tbl(tbl(state.depth).bestiary)
		for _,id in ipairs(SY.Goals.bosses()) do
			local have=SY.Goals.killSource(id)=="lair" and num(kc[id],0) or num(best[id],0)
			card({name="GoalAddBoss"..id,motif="Hunt",title=escape(SY.Goals.bossName(id)),subtitle=fmt(have).." kills",
				actions={{caption="+1",name="GoalBoss1"..id,fn=function() SYS.setGoal("kills",id,have+1) end},
					{caption="+10",name="GoalBoss10"..id,fn=function() SYS.setGoal("kills",id,have+10) end},
					{caption="+100",name="GoalBoss100"..id,fn=function() SYS.setGoal("kills",id,have+100) end}}})
		end
	end
end

-- Price history -----------------------------------------------------------------
-- Sparkline: PR.SPARK bars (6 hours each, oldest left), height by average price.
function SYS.spark(body,nextOrder,s)
	local spark=tbl(s.spark)
	local hi=0
	for _,v in ipairs(spark) do hi=math.max(hi,num(v,0)) end
	local h=compactAtlas and 44 or 56
	local well=make("Frame",body,{Name="Sparkline",BackgroundColor3=track,BackgroundTransparency=.35,Size=UDim2.new(1,0,0,h+8),LayoutOrder=nextOrder(),BorderSizePixel=0})
	make("UICorner",well,{CornerRadius=UDim.new(0,8)})
	make("UIStroke",well,{Color=UI.line,Thickness=1})
	local n=math.max(1,#spark)
	local lo=hi
	for _,v in ipairs(spark) do if num(v,0)>0 then lo=math.min(lo,num(v,0)) end end
	for i,v in ipairs(spark) do
		v=num(v,0)
		-- Scale between 35% (cheapest) and 100% (dearest) so small moves still show.
		local f=if v<=0 or hi<=0 then .04 elseif hi==lo then .7 else .35+.65*(v-lo)/(hi-lo)
		local bar=make("Frame",well,{Name="Bar"..i,AnchorPoint=Vector2.new(0,1),Position=UDim2.new((i-1)/n,2,1,-4),Size=UDim2.new(1/n,-3,0,math.max(2,math.floor((h-2)*f))),
			BackgroundColor3=v>0 and (i==n and gold or mint) or UI.line,BackgroundTransparency=v>0 and .15 or .5,BorderSizePixel=0})
		make("UICorner",bar,{CornerRadius=UDim.new(0,2)})
	end
	return well
end
function SYS.priceLines(s)
	local lines={}
	if s.avg7 then
		table.insert(lines,"24h avg "..(s.avg24 and fmt(s.avg24) or "—").."  ·  24h volume "..fmt(num(s.vol24,0)).."  ·  last "..(s.last and fmt(s.last) or "—"))
		table.insert(lines,"7d avg "..fmt(s.avg7).."  ·  7d range "..fmt(num(s.lo7,0)).."–"..fmt(num(s.hi7,0)).."  ·  7d volume "..fmt(num(s.vol7,0)))
		-- §33 QC M1: few distinct traders: the figures may not reflect a real market.
		if s.thin then table.insert(lines,paint("Thin market: fewer than "..fmt(num(SYS.data() and SYS.data().Prices.THIN,3)).." traders in any hour of this window","E8806A")) end
	else
		table.insert(lines,"No player trades in the last 7 days.")
	end
	return lines
end
-- Price history card (Bazaar book view or a price check).
function SYS.historyCard(item,s,name)
	if type(s)~="table" or not SYS.data() then return end
	card({name=name or "PriceHistory",item=item,title="Price history  ·  "..escape(itemName(item)),
		subtitle="Hourly median prices, last 7 days (each bar 6 hours, newest right)",
		lines=SYS.priceLines(s),after=function(body,nextOrder) SYS.spark(body,nextOrder,s) end})
end
-- Latest known summary for an item (price checks first, then the open Bazaar view).
function SYS.summaryFor(item)
	for _,s in ipairs(tbl(SYS.state().prices)) do if type(s)=="table" and s.item==item then return s end end
	local view=tbl(tbl(state.economy).bazaar)
	if view.item==item and type(view.history)=="table" then return view.history end
	return nil
end
function SYS.groups()
	local out={}
	for _,g in ipairs(tbl(Data.Economy and Data.Economy.bazaarGroups)) do table.insert(out,g) end
	table.insert(out,"Gear")
	return out
end
function SYS.gearItems()
	local list={}
	local E=Data.Economy
	for id,def in pairs(tbl(Data.Items)) do
		if type(def)=="table" and E and E.auctionCategory(id) and (num(tbl(state.items)[id],0)>0 or def.rarity=="Legendary" or def.rarity=="Mythic") then table.insert(list,id) end
	end
	table.sort(list,function(a,b) return itemName(a)<itemName(b) end)
	return list
end
function SYS.drawPrices()
	heading("PRICE HISTORY    /    7 DAYS, EVERY SERVER")
	if not SYS.data() or not Pages.econ then dataMissing() return end
	local latest=tbl(SYS.state().prices)[1]
	if type(latest)=="table" then SYS.historyCard(latest.item,latest,"PriceLatest") end
	sectionBar(SYS.groups(),SYS.priceGroup,function(name) SYS.priceGroup=name SYS.pricePage=1 render() end,{small=true,prefix="PriceGroup",maxPer=6})
	local list=SYS.priceGroup=="Gear" and SYS.gearItems() or Pages.econ.commodities(SYS.priceGroup)
	if #list==0 then row("Nothing to check","Items in this group appear once you hold one (gear) or once the item list loads.") return end
	-- §33 QC L5: pages of SYS.PRICE_PAGE items, so every item in a big group is reachable.
	local pages=math.max(1,math.ceil(#list/SYS.PRICE_PAGE))
	SYS.pricePage=math.clamp(num(SYS.pricePage,1),1,pages)
	local first=(SYS.pricePage-1)*SYS.PRICE_PAGE
	if pages>1 then
		local page=SYS.pricePage
		card({name="PricePager",motif="Ledger",title=escape(SYS.priceGroup).."  ·  page "..page.." of "..pages,
			subtitle=fmt(first+1).."–"..fmt(math.min(#list,first+SYS.PRICE_PAGE)).." of "..fmt(#list).." items",
			actions={{caption="Previous",name="PricePrev",disabled=page<=1,reason=page<=1 and "First page." or nil,fn=function() SYS.pricePage=page-1 render() end},
				{caption="Next",name="PriceNext",disabled=page>=pages,reason=page>=pages and "Last page." or nil,fn=function() SYS.pricePage=page+1 render() end}}})
	end
	local size=compactAtlas and 48 or 58
	local grid=gridHolder(UDim2.fromOffset(size,size),6)
	for i=first+1,math.min(#list,first+SYS.PRICE_PAGE) do
		local id=list[i]
		local cell=tile(grid,"Price"..id,i-first,function()
			SYS.priceItem=id
			send("priceCheck",id)
		end)
		make("UIStroke",cell,{Color=id==SYS.priceItem and gold or slate,Transparency=id==SYS.priceItem and 0 or .5,Thickness=id==SYS.priceItem and 2 or 1})
		local art=itemIcon(cell,id,size-10)
		art.Position=UDim2.fromOffset(5,5)
	end
	heading("RECENT CHECKS")
	local any=false
	for i,s in ipairs(tbl(SYS.state().prices)) do
		if type(s)=="table" and i>1 then
			any=true
			card({name="PriceCheck"..tostring(s.item),item=s.item,title=escape(itemName(s.item)),lines=SYS.priceLines(s),
				actions={{caption="Refresh",name="PriceRefresh"..tostring(s.item),fn=function() send("priceCheck",s.item) end}}})
		end
	end
	if not any then row("Tap an item","Its 7-day trade history, 24h average and volume appear here. Every trade on the Bazaar and the Auction House counts, on every server.") end
end
-- Item tooltips / satchel detail (any client script): ReplicatedStorage.IslePriceCheckLocal:Invoke(itemId, refresh)
-- returns {text, summary} from the last known history (nil when unknown); refresh=true also asks the server.
do
	local fn=ReplicatedStorage:FindFirstChild("IslePriceCheckLocal")
	if not fn then
		fn=Instance.new("BindableFunction")
		fn.Name="IslePriceCheckLocal"
		fn.Parent=ReplicatedStorage
	end
	fn.OnInvoke=function(item,refresh)
		if type(item)~="string" or #item>64 then return nil end
		-- §33 QC M3: a tooltip refresh asks the server at most once per item every SYS.REFRESH_GAP seconds.
		if refresh==true and send and Data and Data.Systems and Data.Systems.Prices.keyFor(item) then
			local now=os.clock()
			if now>=(SYS.refreshAt[item] or 0) then
				SYS.refreshAt[item]=now+SYS.REFRESH_GAP
				send("priceCheck",item,true)
			end
		end
		local s=SYS.summaryFor(item)
		if not s or not SYS.data() then return nil end
		return {text=SYS.data().Prices.text(s),summary=s}
	end
end

-- XP calculator -----------------------------------------------------------------
function SYS.drawCalculator()
	heading("XP CALCULATOR")
	local SY=SYS.data()
	if not SY or type(Data.XP_TABLE)~="table" then dataMissing() return end
	local CA=SY.Calc
	local list=CA.skills()
	if not table.find(list,SYS.calcSkill) then SYS.calcSkill=list[1] or "Mining" end
	sectionBar(list,SYS.calcSkill,function(name) SYS.calcSkill=name SYS.calcTarget=nil render() end,{small=true,prefix="CalcSkill",maxPer=compactAtlas and 4 or 7})
	local skill=SYS.calcSkill
	local info=skillsOf(state)[skill] or EMPTY
	local lvl=num(info.level,1)
	local xp=num(info.xp,num(tbl(state.xp)[skill],0))
	local target=math.clamp(num(SYS.calcTarget,math.min(99,lvl+1)),math.min(99,lvl+1),99)
	SYS.calcTarget=target
	local rate=num(tbl(SYS.state().rates)[skill],0)
	local plan=CA.plan(xp,target,1)
	local function step(d) return function() SYS.calcTarget=math.clamp(target+d,math.min(99,lvl+1),99) render() end end
	card({name="CalcTarget",motif="Hero",title=escape(skill).."  "..fmt(lvl).."  →  "..fmt(target),
		subtitle=fmt(xp).." XP now  ·  "..fmt(plan.goalXp).." XP at level "..fmt(target),
		lines={"<b>"..fmt(plan.remaining).."</b> XP to go"..(rate>0 and ("  ·  at your "..fmt(rate).." XP/h: about "..SY.Goals.etaText(SY.Goals.eta(plan.remaining,rate))) or "  ·  train for a few minutes to see an ETA")},
		bar={fraction=math.clamp(plan.goalXp>0 and xp/plan.goalXp or 0,0,1),color=gold,caption=fmt(xp).." / "..fmt(plan.goalXp)},
		actions={{caption="−5",name="CalcMinus5",fn=step(-5)},{caption="−1",name="CalcMinus1",fn=step(-1)},{caption="+1",name="CalcPlus1",fn=step(1)},
			{caption="+5",name="CalcPlus5",fn=step(5)},{caption="Set goal",primary=true,name="CalcGoal",fn=function() SYS.setGoal("level",skill,target) end}}})
	heading("ACTIONS    /    BASE XP, NO BOOSTS")
	local actions=CA.actions(skill)
	-- Unlocked actions nearest the player's level first, then the next few locked ones.
	local unlocked,locked={},{}
	for _,a in ipairs(actions) do if a.level<=lvl then table.insert(unlocked,a) else table.insert(locked,a) end end
	local shown={}
	for i=#unlocked,math.max(1,#unlocked-9),-1 do table.insert(shown,unlocked[i]) end
	for i=1,math.min(4,#locked) do table.insert(shown,locked[i]) end
	for _,a in ipairs(shown) do
		local p=CA.plan(xp,target,a.xp)
		local open=a.level<=lvl
		card({name="CalcAction"..a.id,item=itemDef(a.id) and a.id or nil,motif=not itemDef(a.id) and "Hunt" or nil,title=escape(a.name),titleColor=open and ivory or muted,
			subtitle=(a.kind=="gather" and "Gather" or (a.kind=="catch" and "Catch" or "Craft")).."  ·  level "..a.level.."  ·  "..fmt(a.xp).." XP each",
			badge=open and (fmt(num(p.actions,0)).." ×") or paint("LEVEL "..a.level,"E8806A"),badgeColor=open and gold or ember,
			lines={open and (fmt(num(p.actions,0)).." actions to reach level "..fmt(target)) or ("Unlocks at "..escape(skill).." "..a.level)}})
	end
	if #shown==0 then row("No actions","This skill trains from other activities.") end
end

-- Daily stock ---------------------------------------------------------------------
function SYS.stockLeft(key)
	local entry=tbl(tbl(SYS.state().stock).left)[key]
	if type(entry)~="table" then return nil,nil end
	return num(entry[1],0),num(entry[2],0)
end
function SYS.stockText(key)
	local left,lim=SYS.stockLeft(key)
	if not lim then return nil end
	return (left>0 and paint(fmt(left).."/"..fmt(lim).." left today","9EE7D2") or paint("Sold out today ("..fmt(lim)..")","E8806A"))
end
Pages.drawHelper,Pages.drawGoals,Pages.drawPrices,Pages.drawCalculator=SYS.drawHelper,SYS.drawGoals,SYS.drawPrices,SYS.drawCalculator
end

------------------------------------------------------------------------------
-- Menu: the landing page (a SkyBlock-style grid of big icon tiles) and the
-- Settings page (local HUD preferences published as player attributes that
-- hud.client.lua / nav.client.lua read).
------------------------------------------------------------------------------
do
local MENU={
	{id="Skills",motif="Hero",tab="Hero",section="Skills"},{id="Collections",motif="Satchel",tab="Satchel",section="Collections"},
	{id="Recipes",motif="Workshop",tab="Workshop",section="Forge"},{id="Bestiary",motif="Hunt",tab="Hunt",section="Bestiary"},
	{id="Quests",motif="Journal",tab="Journal",section="Quests"},{id="Pets",motif="Co-op",tab="Hero",section="Pets"},
	{id="Wardrobe",title="Wardrobe & Gear",motif="Hero",tab="Hero",section="Gear"},{id="Bank",motif="Ledger",tab="Ledger",section="Bank"},
	{id="Market",motif="Ledger",tab="Ledger",section="Orders"},{id="Satchel",motif="Satchel",hud="satchel"},
	{id="Chart",title="Sky Chart",motif="Map",hud="warpmap"},{id="Settings",motif="Settings",tab="Menu",section="Settings"},
	{id="Renown",title="Isle Renown",motif="Journal",tab="Menu",section="Renown"}, -- §31 MMO Features
}
local function caption(id)
	local d=depth() or EMPTY
	if id=="Skills" then return "Total level "..fmt(num(d.totalLevel,0))
	elseif id=="Collections" then local n=0 for _,c in pairs(tbl(d.collections)) do if type(c)=="table" and num(c.tier,0)>0 then n+=1 end end return n.." unlocked"
	elseif id=="Recipes" then return "Stations & crafting"
	elseif id=="Bestiary" then local n=0 for _,k in pairs(tbl(d.bestiary)) do n+=num(k,0) end return fmt(n).." creatures slain"
	elseif id=="Quests" then local j=tbl(state.journal) local ready=0 for _,q in ipairs(tbl(j.quests)) do if type(q)=="table" and q.ready then ready+=1 end end return ready>0 and (ready.." ready to claim") or (fmt(num(j.questPoints,0)).." quest points")
	elseif id=="Pets" then return #tbl(d.pets).." companions"
	elseif id=="Wardrobe" then local n=0 for _ in pairs(tbl(d.equipment)) do n+=1 end return n.." slots equipped"
	elseif id=="Bank" then return "◆ "..fmt(num(state.bank,0)).." banked"
	elseif id=="Market" then return "Bazaar & auctions"
	elseif id=="Satchel" then return "Inventory · E"
	elseif id=="Chart" then return "Warp map · M"
	elseif id=="Renown" then local r=tbl(state.renown) return "Level "..fmt(num(r.level,0)).."  ·  "..tostring(r.title or "Driftling")
	end
	return "Preferences"
end
function Pages.drawMenu()
	heading("MAIN MENU / "..(state.ironman and "IRONMAN" or "VOYAGER"))
	local width=contentWidth()
	local cols=width>=640 and 4 or (width>=400 and 3 or 2)
	local cell=math.floor((width-6-(cols-1)*8)/cols)
	-- Desktop: tall icon-over-title tiles (SkyBlock menu); phones: icon-left rows.
	local tall=compactAtlas and 64 or 124
	local grid=gridHolder(UDim2.fromOffset(cell,tall),8)
	grid.Name="MenuGrid"
	for i,t in ipairs(MENU) do
		local b=tile(grid,"Menu"..t.id,i,function()
			if t.hud then closeAtlas();UI.hudChannel:Fire(t.hud) return end
			Pages.openTo(t.tab,t.section)
			UI.slide()
		end)
		UI.T.rim(b,1.5)
		local title,sub
		if compactAtlas then
			local icon=motif(b,t.motif,34)
			icon.AnchorPoint=Vector2.new(0,.5)
			icon.Position=UDim2.new(0,10,.5,0)
			title=label(b,t.id,52,12,UDim.new(1,-60),20,UI.heavy,14,ivory)
			sub=label(b,caption(t.id),52,32,UDim.new(1,-60),18,regular,12,muted)
		else
			local icon=motif(b,t.motif,54)
			icon.AnchorPoint=Vector2.new(.5,0)
			icon.Position=UDim2.new(.5,0,0,12)
			title=label(b,t.title or t.id,8,72,UDim.new(1,-16),20,UI.heavy,16,ivory)
			sub=label(b,caption(t.id),8,94,UDim.new(1,-16),18,regular,12,muted)
			title.TextXAlignment,sub.TextXAlignment=Enum.TextXAlignment.Center,Enum.TextXAlignment.Center
		end
		title.Name,sub.Name="Title","Caption"
	end
end
-- §31 MMO Features: Menu › Renown (Isle Renown level, sources, next unlocks and
-- the Wayfarer's Path) and Menu › Resonance (Magical Power tuning; the server
-- requires a recent visit to the Resonance Keeper and charges the switch fee).
function Pages.drawRenown()
	local r=tbl(state.renown)
	local level=num(r.level,0)
	heading("ISLE RENOWN / LEVEL "..fmt(level))
	local hex=type(r.color)=="string" and #r.color==6 and r.color or "FFFFFF"
	local perks={}
	for stat,v in pairs(tbl(r.stats)) do perks[stat]=v end
	card({name="RenownLevel",motif="Journal",title=paint("✦ "..fmt(level).."  "..escape(tostring(r.title or "Driftling")),hex),
		subtitle=fmt(num(r.xp,0)).." renown  ·  "..fmt(num(r.slots,0)).." bonus accessory slots",
		detail="One account level for everything you do. Renown is counted from your whole journal, so nothing is ever lost or counted twice.",
		lines={next(perks) and ("Renown perks: "..statText(perks)) or "Renown perks unlock at level 10."},
		bar={fraction=num(r.into,0)/math.max(1,num(r.need,100)),color=rgb(hex),caption=fmt(num(r.into,0)).." / "..fmt(num(r.need,100)).." to level "..fmt(level+1)}})
	local upcoming={}
	for _,u in ipairs(tbl(r.next)) do if type(u)=="table" then table.insert(upcoming,"Level "..fmt(num(u.level,0)).."  ·  "..escape(tostring(u.text))) end end
	if #upcoming>0 then card({name="RenownNext",motif="Journal",title="Next unlocks",lines=upcoming}) end
	local g=tbl(state.guide)
	if g.title then
		local owed=num(g.owed,0)
		card({name="RenownPath",motif="Journal",title="Wayfarer's Path",subtitle=g.complete and paint("Complete","6FE3C8") or ("Step "..fmt(num(g.step,1)).." of "..fmt(num(g.total,10))),
			detail=escape(tostring(g.title))..(g.detail and (" — "..escape(tostring(g.detail))) or ""),
			pips={total=num(g.total,10),filled=num(g.done,0),color=mint},
			actions=owed>0 and {{caption="Claim "..fmt(owed).." coins",primary=true,name="GuideClaim",fn=function() send("guideClaim") end}} or nil})
	end
	heading("RENOWN SOURCES")
	local byId=Data and Data.Renown and Data.Renown.SourceById or {}
	for _,s in ipairs(tbl(r.sources)) do
		if type(s)=="table" then
			local def=tbl(byId[s.id]) -- rows are {id, xp, count}; names and hints are static data
			card({name="RenownSource"..tostring(s.id),title=escape(tostring(def.name or s.name or s.id)),badge=fmt(num(s.xp,0)),badgeColor=gold,
				subtitle=fmt(num(s.count,0)).." counted",detail=escape(tostring(def.hint or s.hint or ""))})
		end
	end
end
function Pages.drawResonance()
	local res=tbl(state.resonance)
	local R=Data and Data.Resonance
	local power=num(res.power,0)
	heading("RESONANCE / "..fmt(power).." MAGICAL POWER")
	local visiting=num(res.visitIn,0)>0
	card({name="ResonanceInfo",motif="Hero",title=res.id and ("Tuned: "..escape(tostring(res.id))) or "No resonance yet",
		subtitle=visiting and paint("The Resonance Keeper is listening","6FE3C8") or "Visit the Resonance Keeper in Compass Quay to tune",
		detail="Your accessory bag's Magical Power becomes stats in the resonance you pick. The first tuning is free; a change costs "..fmt(num(res.fee,0)).." coins"..(num(res.readyIn,0)>0 and (" (settling "..fmt(num(res.readyIn,0)).."s)") or "")..".",
		lines={res.id and ("Now: "..statText(res.stats)) or nil}})
	if not R then return end
	for _,t in ipairs(R.Templates) do
		local preview=R.stats(t.id,power)
		local current=res.id==t.id
		local reason=(current and "Already tuned.") or (power<t.minPower and ("Needs "..t.minPower.." Magical Power.")) or (not visiting and "Visit the Resonance Keeper first.") or nil
		card({name="Resonance"..t.id,motif="Hero",title=paint(escape(t.name),t.color),subtitle=escape(t.text),badge=current and paint("ACTIVE","6FE3C8") or nil,
			lines={next(preview) and ("At your power: "..statText(preview)) or ("Unlocks at "..t.minPower.." Magical Power")},
			actions={{caption=current and "Active" or "Tune",primary=reason==nil,disabled=reason~=nil,reason=reason,name="Tune"..t.id,fn=function() send("resonanceSet",t.id) end}}})
	end
end
local SETTINGS={
	{attr="IsleSettingPinSatchel",title="Pin the satchel",detail="Keep the satchel open beside the sidebar while you play (desktop).",default=false},
	{attr="IsleSettingXpDrops",title="XP drops",detail="Floating +XP counters and the skill progress toast when you gain experience.",default=true},
	{attr="IsleSettingMinimap",title="Minimap",detail="The top-left minimap with region name and coordinates (its Map button folds the map away).",default=true},
	{attr="IsleSettingReducedMotion",title="Reduced motion",detail="XP drops and level-up banners appear in place instead of sliding and scaling.",default=false},
}
-- The live value of a setting (the HUD's Pin button and closing the satchel
-- change IsleSettingPinSatchel too, so a toggle never acts on a stale card).
function Pages.settingValue(o)
	local value=player:GetAttribute(o.attr)
	if value==nil then value=o.default end
	return value==true
end
-- Re-render the Settings page when a setting changes elsewhere while it shows.
local watchedSettings=table.clone(SETTINGS)
table.insert(watchedSettings,{attr="IsleSettingGraphics"}) -- §35 graphics tier
for _,o in ipairs(watchedSettings) do
	player:GetAttributeChangedSignal(o.attr):Connect(function()
		if UI.atlasOpen and current=="Menu" and sectionOf and sectionOf.Menu=="Settings" and render then render() end
	end)
end
-- §35 QC L6: a Settings change is applied locally at once and saved on the
-- profile through the `setting` verb ("Attr=value"; the server whitelists it
-- and re-applies saved values on join). Saves are coalesced per attribute and
-- sent one at a time outside the action queue (no toast, no snapshot).
UI.settingSaves,UI.settingSaving={},false
function UI.saveSetting(attr,value)
	player:SetAttribute(attr,value)
	UI.settingSaves[attr]=value
	if UI.settingSaving then return end
	UI.settingSaving=true
	task.spawn(function()
		while true do
			local nextAttr,nextValue=next(UI.settingSaves)
			if nextAttr==nil then break end
			UI.settingSaves[nextAttr]=nil
			local action=ReplicatedStorage:FindFirstChild("IsleAction") -- (the `remote` local is declared further down)
			if action then pcall(function() action:InvokeServer("setting",nextAttr.."="..tostring(nextValue)) end) end
		end
		UI.settingSaving=false
	end)
end
-- §35 QC L7: the graphics card reads its tier text from AetherLighting
-- (L.Tiers[*].detail, the same table the director runs), resolved lazily.
function UI.lightingRules()
	if UI.lightingModule==nil then
		local object=ReplicatedStorage:FindFirstChild("AetherLighting")
		if object then
			local ok,rules=pcall(require,object)
			UI.lightingModule=ok and type(rules)=="table" and rules or false
		end
	end
	return UI.lightingModule or nil
end
function Pages.drawSettings()
	heading("SETTINGS / SAVED TO YOUR JOURNAL")
	for _,o in ipairs(SETTINGS) do
		local value=Pages.settingValue(o)
		card({name="Setting"..o.attr,motif="Settings",title=o.title,subtitle=value and paint("On","6FE3C8") or paint("Off","A9B4C0"),detail=o.detail,
			actions={{caption=value and "Turn off" or "Turn on",primary=not value,name="Toggle"..o.attr,fn=function()
				UI.saveSetting(o.attr,not Pages.settingValue(o))
				render()
			end}}})
	end
	-- Graphics (§35): lighting.client.lua reads IsleSettingGraphics (it publishes
	-- the device default on first run: phones Balanced, low quality Performance).
	local GA="IsleSettingGraphics"
	local LR=UI.lightingRules()
	local tiers={}
	for _,id in ipairs(LR and LR.TIER_ORDER or {"High","Balanced","Performance"}) do
		local def=LR and LR.Tiers and LR.Tiers[id]
		table.insert(tiers,{id=id,text=def and type(def.detail)=="string" and def.detail or nil})
	end
	local now=player:GetAttribute(GA)
	local actions,detail={},nil
	for _,t in ipairs(tiers) do
		local on=now==t.id
		table.insert(actions,{caption=(on and "✓ " or "")..t.id,primary=on,name="Graphics"..t.id,fn=function() UI.saveSetting(GA,t.id) render() end})
		if on then detail=t.text end
	end
	card({name="SettingGraphics",motif="Settings",title="Graphics quality",subtitle=paint(type(now)=="string" and now or "Automatic","6FE3C8"),
		detail=type(detail)=="string" and detail or "Chosen from your device.",actions=actions})
	card({name="SettingKeys",motif="Journal",title="Keys",detail="J  menu & atlas   ·   E / Tab  satchel   ·   M  Sky Chart (warp map)   ·   right-click (long-press) an item for its options   ·   drag items to reorder"})
end
end

------------------------------------------------------------------------------
-- Navigation: the Menu plus six primary tabs, each with a section switcher.
------------------------------------------------------------------------------
local tabOrder={"Menu","Journal","Hero","Satchel","Workshop","Hunt","Ledger"}
local sectionLists={
	Menu={"Home","Renown","Resonance","Settings"}, -- §31: Renown, Resonance
	Journal={"Bearing","Quests","Helper","Goals","Diaries","Construction","Regions","Crew","Calendar","Council","Agility","Commissions","Collection Log","Museum","Motes","Factions"}, -- §33: Helper, Goals
	Hero={"Skills","Mastery","Gear","Combat","Spellbook","Prayer","Enchant","Reforge","Accessories","Pets","Calculator"}, -- §33: Calculator
	Satchel={"Items","Collections","Trails"},
	Workshop={"Forge","Hearth","Cauldron","Workbench","Crafting","Beaconry","Workers","Home","Garden","Contests"}, -- §37: Beaconry; §39: Contests
	Hunt={"Slayer","Bestiary","Dungeon","Essence","Bosses","Hunter","Thieving","Minigames","Trophies"}, -- §39: Trophies
	Ledger={"Bank","Market","Orders","Auctions","Prices","Merchant","Vendors"}, -- §33: Prices
}
sectionOf={Menu="Home",Journal="Bearing",Hero="Skills",Satchel="Items",Workshop="Forge",Hunt="Slayer",Ledger="Bank"}
local drawers={
	Menu={Home=function() Pages.drawMenu() end,Renown=function() Pages.drawRenown() end,Resonance=function() Pages.drawResonance() end,Settings=function() Pages.drawSettings() end},
	Journal={Bearing=Pages.drawBearing,Quests=Pages.drawQuests,Diaries=Pages.drawDiaries,Construction=Pages.drawConstruction,Regions=Pages.drawRegions,Crew=Pages.drawCoop,Calendar=Pages.drawCalendar,Council=function() Pages.drawCouncil() end,Agility=Pages.drawAgility,
		Commissions=Pages.drawCommissions,["Collection Log"]=Pages.drawCollectionLog,Museum=Pages.drawMuseum, -- Commissions & Logs
		Motes=Pages.drawMotes,Factions=Pages.drawFactions, -- Exploration & Factions
		Helper=Pages.drawHelper,Goals=Pages.drawGoals}, -- §33 quest helper, goal board
	Hero={Skills=Pages.drawSkills,Mastery=Pages.drawMastery,Gear=Pages.drawGear,Combat=Pages.drawCombat,Spellbook=Pages.drawSpellbook,Prayer=Pages.drawPrayer,Enchant=Pages.drawEnchant,Reforge=function() Pages.drawReforge() end,Accessories=Pages.drawAccessories,Pets=Pages.drawPets,Calculator=Pages.drawCalculator},
	Satchel={Items=Pages.drawItems,Collections=Pages.drawCollections,Trails=Pages.drawTrails},
	Workshop={Forge=function() Pages.drawStation("Forge") end,Hearth=function() Pages.drawStation("Hearth") end,Cauldron=function() Pages.drawStation("Cauldron") end,
		Workbench=function() Pages.drawStation("Workbench") end,Crafting=Pages.drawCrafting,Beaconry=Pages.drawBeaconry,Workers=Pages.drawWorkers,Home=Pages.drawHome,Garden=Pages.drawGarden,
		Contests=function() Pages.drawContests() end}, -- §39
	Hunt={Slayer=Pages.drawSlayer,Bestiary=Pages.drawBestiary,Dungeon=Pages.drawDungeon,Essence=Pages.drawEssence,Hunter=Pages.drawHunter,Thieving=Pages.drawThieving,Minigames=Pages.drawMinigames,Bosses=Pages.drawBosses,
		Trophies=function() Pages.drawTrophies() end}, -- §39
	Ledger={Bank=Pages.drawBank,Market=Pages.drawMarket,Orders=Pages.drawOrders,Auctions=Pages.drawAuctions,Merchant=Pages.drawMerchant,Vendors=Pages.drawVendors,Prices=Pages.drawPrices},
}
local function resetTransient()
	if Pages.TT then Pages.TT.flush() end -- Treasure Trails: send buffered puzzle moves on page change
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
		UI.slide()
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
			local on=name==current
			local icon=b:FindFirstChild("TabIcon")
			local caption=b:FindFirstChild("TabCaption")
			local glow=b:FindFirstChild("TabGlow")
			if railMode and UI.railGrid then
				-- Short phones: six stacked rows would be under UI.TOUCH, so the rail
				-- becomes a 2 × 3 grid of icon-over-caption tiles.
				local c,r=(i-1)%2,(i-1)//2
				local rowsN=math.ceil(n/2)
				b.Position=UDim2.new(c/2,c==0 and 0 or 2,r/rowsN,0)
				b.Size=UDim2.new(.5,-2,1/rowsN,-4)
				if icon then icon.Size=UDim2.fromOffset(22,22);icon.Position=UDim2.new(.5,-11,.5,-21) end
				if caption then caption.Position=UDim2.new(0,1,.5,3);caption.Size=UDim2.new(1,-2,0,16);caption.TextXAlignment=Enum.TextXAlignment.Center end
				if glow then glow.AnchorPoint=Vector2.new(.5,1);glow.Position=UDim2.new(.5,0,1,-1);glow.Size=UDim2.new(.44,0,0,3) end
			elseif railMode then
				b.Position=UDim2.new(0,0,(i-1)/n,0)
				b.Size=UDim2.new(1,0,1/n,-5)
				if icon then icon.Size=UDim2.fromOffset(22,22);icon.Position=UDim2.new(0,10,.5,-11) end
				if caption then caption.Position=UDim2.fromOffset(38,0);caption.Size=UDim2.new(1,-40,1,0);caption.TextXAlignment=Enum.TextXAlignment.Left end
				if glow then glow.AnchorPoint=Vector2.new(0,.5);glow.Position=UDim2.new(0,0,.5,0);glow.Size=UDim2.new(0,3,.56,0) end
			else
				b.Position=UDim2.new((i-1)/n,0,0,0)
				b.Size=UDim2.new(1/n,-6,1,0)
				local s=compactAtlas and 20 or 28
				if icon then icon.Size=UDim2.fromOffset(s,s);icon.Position=UDim2.new(.5,-s/2,0,compactAtlas and 4 or 6) end
				if caption then caption.Position=UDim2.fromOffset(2,compactAtlas and 25 or 36);caption.Size=UDim2.new(1,-4,0,18);caption.TextXAlignment=Enum.TextXAlignment.Center end
				if glow then glow.AnchorPoint=Vector2.new(.5,1);glow.Position=UDim2.new(.5,0,1,-1);glow.Size=UDim2.new(.44,0,0,3) end
			end
			b.BackgroundTransparency=on and 0 or 1
			local rim=b:FindFirstChild("Rim")
			if rim then rim.Transparency=on and .05 or 1 end
			if caption then
				caption.TextColor3=on and gold or rgb("B7C8CB")
				caption.Font=on and UI.heavy or bold
			end
			if glow then glow.Visible=on end
		end
	end
end
-- Page transition: the page slides up into place.
function UI.slide()
	local final=scroll.Position
	scroll.Position=final+UDim2.fromOffset(0,10)
	TweenService:Create(scroll,TweenInfo.new(.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=final}):Play()
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
	local headHeight=railMode and 48 or (compactAtlas and 58 or 70)
	UI.head.Size=UDim2.new(1,0,0,headHeight)
	UI.headRule.Position=UDim2.new(0,14,0,headHeight-1)
	UI.kicker.Visible=not compactAtlas
	local crest=railMode and 32 or (compactAtlas and 38 or 44)
	UI.crest.Size=UDim2.fromOffset(crest,crest)
	UI.crest.Position=UDim2.fromOffset(railMode and 12 or (compactAtlas and 12 or 16),(headHeight-crest)//2)
	UI.title.Position=UDim2.fromOffset(crest+(railMode and 20 or 24),railMode and 7 or (compactAtlas and 11 or 25))
	UI.title.Size=UDim2.new(1,-crest-220,0,railMode and 32 or 36)
	UI.title.TextSize=railMode and 14 or (compactAtlas and 15 or 18)
	UI.kicker.Position=UDim2.fromOffset(crest+25,12)
	local closeSize=compactAtlas and UI.TOUCH or 40
	UI.close.Size=UDim2.fromOffset(closeSize,closeSize)
	UI.close.Position=UDim2.new(1,-closeSize-(railMode and 20 or 18),0,(headHeight-closeSize)//2)
	UI.coins.Visible=size.X>=460
	UI.coins.Position=UDim2.new(1,-closeSize-(railMode and 30 or 28),.5,0)
	UI.coins.Size=UDim2.fromOffset(railMode and 118 or 132,railMode and 28 or 32)
	UI.coinText.Text=fmt(num(state.coins,0))
	-- Rail rows must stay UI.TOUCH tall; when six do not fit, a 2-column grid (wider rail).
	UI.railGrid=railMode and (size.Y-headHeight-18)/#tabOrder-5<UI.TOUCH
	if railMode then
		local railWidth=UI.railGrid and 128 or 112
		tabs.Position=UDim2.fromOffset(12,headHeight+8)
		tabs.Size=UDim2.new(0,railWidth,1,-headHeight-18)
		scroll.Position=UDim2.fromOffset(railWidth+22,headHeight+8)
		scroll.Size=UDim2.new(1,-railWidth-34,1,-headHeight-16)
	else
		local tabHeight=compactAtlas and 46 or 60
		tabs.Position=UDim2.fromOffset(14,headHeight+6)
		tabs.Size=UDim2.new(1,-28,0,tabHeight)
		local contentTop=headHeight+6+tabHeight+10
		scroll.Position=UDim2.fromOffset(14,contentTop)
		scroll.Size=UDim2.new(1,-28,1,-contentTop-36)
	end
	UI.footer.Visible=not railMode
	UI.hint.Visible=not railMode and not compactAtlas
	UI.footRule.Visible=not railMode
	UI.layoutSidebar()
	UI.layoutActionBar()
	UI.refreshSidebar()
	UI.goal.Text = synced and UI.objective() or "Charting the islands…"
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
	THUMBS.decorUsed = 0
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
	UI.footer.Text = state.preview and "STUDIO PRACTICE  ·  PROGRESS IS TEMPORARY"
		or (string.upper(current).."   ›   "..string.upper(tostring(sectionOf[current] or "")))
	UI.hint.Text = Input.GamepadEnabled and "Ⓨ ATLAS   ·   Ⓑ CLOSE" or "J  OPEN / CLOSE   ·   CLICK OUTSIDE TO CLOSE"
end
for _, name in ipairs(tabOrder) do
	local b=make("TextButton",tabs,{Name=name.."Button",Text="",AutoButtonColor=false,BackgroundColor3=UI.raised,BackgroundTransparency=1,BorderSizePixel=0,Selectable=true})
	make("UICorner",b,{CornerRadius=UDim.new(0,11)})
	local rim=make("UIStroke",b,{Name="Rim",Color=gold,Thickness=1,Transparency=1})
	make("UIGradient",rim,{Rotation=90,Color=ColorSequence.new(UI.white,Color3.new(.3,.3,.3))})
	UI.sheen(b,1,.6)
	pressable(b)
	b.Activated:Connect(function()
		current = name
		resetTransient()
		scroll.CanvasPosition = Vector2.zero
		render()
		UI.slide()
		refreshSection(name,sectionOf[name])
	end)
	local tabIcon=motif(b,name,28)
	tabIcon.Name="TabIcon"
	tabIcon.BackgroundTransparency=1
	tabIcon:FindFirstChild("Rim").Enabled=false
	local tabCaption=label(b,name,2,36,UDim.new(1,-4),18,bold,13,ivory)
	tabCaption.Name="TabCaption"
	tabCaption.TextXAlignment=Enum.TextXAlignment.Center
	tabCaption.TextScaled=true
	make("UITextSizeConstraint",tabCaption,{MinTextSize=11,MaxTextSize=13})
	local glow=make("Frame",b,{Name="TabGlow",BackgroundColor3=gold,BorderSizePixel=0,Visible=false})
	make("UICorner",glow,{CornerRadius=UDim.new(1,0)})
	make("UIStroke",glow,{Color=gold,Thickness=2,Transparency=.6})
	tabButtons[name] = b
end
layoutTabs()
atlas:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if atlas.Visible then render() end end)
openAtlas = function()
	if current == nil then current = "Menu" end
	atlas.Visible = true
	atlas.Position=UDim2.new(.5,0,.5,16)
	UI.atlasScale.Scale=.96
	shade.BackgroundTransparency=1
	TweenService:Create(atlas,TweenInfo.new(.22,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Position=UDim2.fromScale(.5,.5)}):Play()
	TweenService:Create(UI.atlasScale,TweenInfo.new(.26,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
	TweenService:Create(shade,TweenInfo.new(.2),{BackgroundTransparency=.35}):Play()
	hud.Visible = false
	UI.atlasOpen = true
	actionBar.Visible = false
	shade.Visible = true
	render()
	if send then send("state") end
	refreshSection(current,sectionOf[current])
	if Input.GamepadEnabled then
		GuiService.SelectedObject = tabButtons[current]
	end
end
UI.openAtlas=function() current="Menu";sectionOf.Menu="Home";resetTransient();scroll.CanvasPosition=Vector2.zero;openAtlas() end
local function openTo(tab,section)
	current=tab
	if section then sectionOf[tab]=section end
	resetTransient()
	scroll.CanvasPosition=Vector2.zero
	openAtlas()
end
Pages.openTo=openTo
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
	if maxHealth then
		UI.healthText.Text=fmt(math.max(0,math.floor(health or 0))).."/"..fmt(math.floor(maxHealth)).." ❤"
		UI.setMeter(UI.healthFill,(health or 0)/math.max(1,maxHealth))
	else
		UI.healthText.Text="—"
		UI.setMeter(UI.healthFill,0)
	end
	local defense=num(stats.defense,nil) or num(legacy.defense,nil)
	UI.defenseText.Text=defense and (fmt(defense)..' ❈'..(UI.lay().tiny and "" or ' <font color="#A9B4C0">Defense</font>')) or "—"
	-- Mana: live attributes from the combat server; before the first push, max
	-- mana is Intelligence (full).
	local maxMana=num(player:GetAttribute("MaxMana"),nil) or num(stats.intelligence,nil)
	local mana=num(player:GetAttribute("Mana"),nil) or maxMana
	if maxMana then
		UI.manaText.Text=fmt(math.max(0,math.floor(mana or 0))).."/"..fmt(math.floor(maxMana)).." ✎ Mana"
		UI.setMeter(UI.manaFill,(mana or 0)/math.max(1,maxMana))
	else
		UI.manaText.Text="—"
		UI.setMeter(UI.manaFill,0)
	end
end
player:GetAttributeChangedSignal("Mana"):Connect(function() updateVitals() end)
player:GetAttributeChangedSignal("MaxMana"):Connect(function() updateVitals() end)
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
UI.xpToken,UI.bannerQueue,UI.bannerBusy=0,{},false
-- XP gains go to hud.client.lua (OSRS XP drops + the skill progress toast)
-- through IsleXpLocal: {{skill, amount, level, fraction, maxed, color}, ...}.
-- UI.lastGains keeps the latest list for tests and tools.
local function showXp(gains)
	UI.lastGains=gains
	if UI.xpChannel then pcall(function() UI.xpChannel:Fire(gains) end) end
end
-- The banner's lane (Theme.hudLayout levelBanner): centred under the top lane
-- on wide screens; on short screens (phones) a slim banner in the top lane
-- between the left column and the XP toast, so it never covers the XP lane.
function UI.placeBanner()
	local slot=UI.lay().levelBanner
	local banner=UI.banner
	banner:FindFirstChild("BannerLimit").MaxSize=Vector2.new(slot.w,slot.h)
	banner.AnchorPoint=Vector2.new(0,0)
	banner.Position,banner.Size=UDim2.fromOffset(slot.x,slot.y),UDim2.fromOffset(slot.w,slot.h)
	UI.bannerSlim=slot.slim
	return slot
end
local function showNextBanner()
	local entry=table.remove(UI.bannerQueue,1)
	local banner=UI.banner
	if not entry then UI.bannerBusy=false;banner.Visible=false;return end
	UI.bannerBusy=true
	UI.placeBanner()
	local view=gui.AbsoluteSize
	local narrow=view and view.X<900
	local short=UI.bannerSlim==true
	UI.bannerTitle.Position=UDim2.fromOffset(76,short and 8 or 17)
	UI.bannerReward.Position=UDim2.fromOffset(76,short and 36 or 50)
	UI.bannerEmblem.Size=UDim2.fromOffset(short and 40 or 48,short and 40 or 48)
	local hex=skillHex(entry.skill)
	UI.bannerTitle.Text=entry.skill.."  "..entry.from.." → "..entry.to
	UI.bannerTitle.TextSize=narrow and 12 or 16
	UI.bannerTitle.TextColor3=rgb(lighten(hex,.45))
	UI.bannerEmblem.BackgroundColor3=rgb(hex)
	UI.bannerInitial.Text=initials(entry.skill)
	local reward=entry.coins>0 and paint("+"..fmt(entry.coins).." coins","F3C66E") or ""
	local perLevel=tbl(skillDef(entry.skill).perLevel)
	if narrow then
		-- One stat on phones so the reward line stays on a single row.
		local first=statKeys(perLevel)[1]
		perLevel=first and {[first]=perLevel[first]} or perLevel
	end
	local stats=statText(perLevel,entry.to-entry.from,"  ")
	UI.bannerReward.Text=reward..(reward~="" and stats~="" and "   ·   " or "")..stats
	banner.Visible=true
	-- Reduced motion (Settings or the device): the banner appears at full size.
	if UI.T.reducedMotion(player) then UI.bannerScale.Scale=1 else
		UI.bannerScale.Scale=.82
		TweenService:Create(UI.bannerScale,TweenInfo.new(.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
	end
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
				table.insert(UI.bannerQueue,{skill=skill,from=old.level,to=new.level,coins=coins})
				if coins>0 then bannered[skill]=true end
			end
		end
	end
	if #gains>0 then
		local list={}
		for i=1,math.min(3,#gains) do
			local gain=gains[i]
			list[i]={skill=gain.skill,amount=gain.amount,level=gain.info.level,fraction=gain.info.fraction,maxed=gain.info.maxed==true,color=lighten(skillHex(gain.skill),.35)}
		end
		showXp(list)
	end
	if #UI.bannerQueue>0 and not UI.bannerBusy then showNextBanner() end
	return bannered
end


------------------------------------------------------------------------------
-- Server wiring
------------------------------------------------------------------------------
UI.relay={equip=true,unequip=true,consume=true,sell=true,accessory=true,petAdopt=true,drop=true,satchelMove=true,satchelSort=true,recall=true,
	rqBuy=true,skillBuy=true,petShop=true,resonanceSet=true,guideClaim=true, -- §31
	helperPin=true,goalSet=true,goalRemove=true,goalClear=true,priceCheck=true, -- §33
	prayerQuickToggle=true, -- §34
	raidHost=true,raidJoin=true,raidLeave=true,raidReady=true,raidChallenge=true,raidStart=true,raidUse=true,raidTitle=true} -- §38 raid.client.lua (party board, raid HUD, Raid Log). §34 quick-prayer orb (one atomic verb, queued, never dropped). Earlier: quantity picker (features.client.lua), Resonance, Path rewards
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
	-- Share every accepted snapshot with the combat HUD (combat.client.lua).
	pcall(function() UI.snapshotChannel:Fire(data) end)
	pcall(Pages.AH.onSnapshot) -- lap tracker best times, trap counter
	pcall(function() Pages.CT.refreshHud() end) -- §39 contest tracker (QC M3: re-stacks with the snapshot)
	pcall(Pages.CLP.observe,data) -- Commissions & Logs: cache full snapshot.logs (compact ones reuse it)
	pcall(Pages.EXP.observe,data) -- Exploration & Factions: cache full snapshot.exploration (compact ones reuse it)
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
	-- §34: price-check replies are silent (data.silent); an explicit (non-quiet)
	-- request still toasts its own reply text, never a hover refresh.
	if data.silent then
		if not quiet and type(data.reply)=="string" and not data.reply:find("price check:",1,true) then notify(data.reply) end
		if type(message)=="string" and message~="" and not quiet then notify(message) end
	elseif not quiet then notify(message) end
	return true
end
local pending = false
-- Satchel / paperdoll / Sky Chart verbs relayed from hud.client.lua wait their
-- turn while a request is in flight (up to 8, then a toast) instead of being
-- dropped. Order is kept: a verb queues whenever a request is pending OR the
-- queue is not empty, and UI.relayDrain is the one place that sends queued
-- verbs, spaced RELAY_GAP s after the previous send so they never land inside
-- the server's 0.24 s action cooldown. A queued verb that meets a request in
-- flight goes back to the front of the queue (the reply drains it).
UI.relayQueue,UI.relayLast,UI.RELAY_GAP={},-math.huge,0.26
function UI.relayDrain(due)
	if UI.relayDraining or #UI.relayQueue==0 or pending then return end
	local wait=math.max(0,UI.RELAY_GAP-(os.clock()-UI.relayLast))
	if wait>0 and not due then
		UI.relayDraining=true
		task.delay(wait,function() UI.relayDraining=false; UI.relayDrain(true) end)
		return
	end
	local nextAction=table.remove(UI.relayQueue,1)
	if pending then table.insert(UI.relayQueue,1,nextAction) return end
	send(nextAction[1],nextAction[2])
end
function UI.relaySend(verb,item)
	if pending or #UI.relayQueue>0 or UI.relayDraining then
		if #UI.relayQueue<8 then table.insert(UI.relayQueue,{verb,item}) else notify("Still working on your last few actions. Try again in a moment.") end
		UI.relayDrain()
		return
	end
	send(verb,item)
end
send = function(action, item, quiet)
	if pending then
		return
	end
	pending = true
	UI.relayLast=os.clock()
	local ok, result = pcall(function()
		return remote:InvokeServer(action, item)
	end)
	pending = false
	local accepted = false
	if ok then
		accepted = accept(result,quiet)
	else
		notify("Your ledger could not be reached. Try again.")
	end
	UI.relayDrain()
	return accepted
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
-- Local channels with the combat HUD (combat.client.lua): snapshots out,
-- verbs (spell bar autocast) and short toasts (denied attacks) in.
do
	local function channel(name)
		local existing=ReplicatedStorage:FindFirstChild(name)
		if existing then return existing end
		local created=Instance.new("BindableEvent")
		created.Name=name
		created.Parent=ReplicatedStorage
		return created
	end
	UI.snapshotChannel=channel("IsleSnapshotLocal")
	UI.xpChannel,UI.hudChannel=channel("IsleXpLocal"),channel("IsleHudLocal")
	local actions,toasts=channel("IsleActionLocal"),channel("IsleToastLocal")
	-- hud.client.lua asks the atlas to open a page ("open", tab, section).
	UI.hudChannel.Event:Connect(function(kind,tab,section)
		if kind=="open" and type(tab)=="string" and sectionLists[tab] then openTo(tab,type(section)=="string" and section or nil) end
	end)
	if actions.Event then
		actions.Event:Connect(function(verb,item)
			if verb=="autocast" and (item==nil or type(item)=="string") then task.spawn(send,"autocast",item)
			-- Satchel / paperdoll / Sky Chart (hud.client.lua): existing validated verbs
			-- plus satchelMove / satchelSort / drop (§29); the server checks everything.
			elseif UI.relay[verb] and (item==nil or (type(item)=="string" and #item<=64)) then task.spawn(UI.relaySend,verb,item)
			-- Prayer quick bar taps (combat HUD): the server validates the prayer.
			elseif verb=="prayer" and type(item)=="string" and #item<=64 then task.spawn(send,"prayer",item)
			-- Exploration & Factions: world mote prompts (motes.client.lua); the server picks the mote.
			elseif verb=="moteCollect" or verb=="moteHint" then task.spawn(send,verb,nil)
			-- The mote layer saw only compact exploration snapshots: ask for the full copy.
			elseif verb=="exploreSync" then task.spawn(send,"exploreSync",nil,true)
			-- A late-starting combat HUD / mote layer asks for the latest snapshot
			-- (a compact exploration is replaced by the cached full copy).
			elseif verb=="snapshot" and synced then
				pcall(function()
					local snap=state
					local ex=type(snap)=="table" and snap.exploration
					local cached=Pages.EXP and Pages.EXP.cache
					snap=table.clone(snap)
					if type(ex)=="table" and ex.compact and cached and cached.rev==ex.rev then snap.exploration=cached end
					-- §34: a replay keeps the original seq and is marked, so the chat router
					-- and pickup feed never print it a second time.
					snap.replay=true
					UI.snapshotChannel:Fire(snap)
				end)
			end
		end)
	end
	if toasts.Event then toasts.Event:Connect(function(text) notify(text) end) end
end
-- Crafting stations and the slayer board set IsleStation on the player; open
-- the matching page. Values may carry a suffix ("Forge:3") so repeats fire.
local stationTabs={Forge="Workshop",Hearth="Workshop",Cauldron="Workshop",Workbench="Workshop",Beaconry="Workshop",Slayer="Hunt",Construction="Journal",Calendar="Journal",
	SkymarkExchange="Ledger",TrackersLodge="Ledger",Garden="Workshop",Commissions="Journal",Museum="Journal",CollectionLog="Journal", -- Commissions & Logs: board / museum prompts
	Jeweller="Workshop",Tannery="Workshop",Glassworks="Workshop", -- Crafting stations (Workshop › Crafting)
	Motes="Journal",Factions="Journal", -- Exploration & Factions: Mote Shrines, faction standards
	Resonance="Menu", -- §31: the Resonance Keeper opens Menu › Resonance
	Contests="Workshop",Trophies="Hunt", -- §39: the Contest Steward and the Trophy Keeper
	Council="Journal"} -- §36: the Council Clerk and the ballot chest open Journal › Council
local function openStation()
	local value=player:GetAttribute("IsleStation")
	if type(value)~="string" then return end
	local station=value:match("^(%a+)")
	local tab=station and stationTabs[station]
	if not tab then return end
	-- Skill vendors (Agility & Hunter): Ledger › Vendors on that vendor's stock.
	if tab=="Ledger" then Pages.AH.vendor=station=="SkymarkExchange" and "Agility" or "Hunter";openTo("Ledger","Vendors") return end
	if tab=="Menu" then openTo("Menu",station) return end -- §31: Resonance Keeper
	if tab=="Workshop" and Pages.CR and Data and Data.Crafting and Data.Crafting.Stations[station] then Pages.CR.station=station;openTo("Workshop","Crafting") return end
	if tab=="Hunt" and station=="Trophies" then openTo("Hunt","Trophies") return end -- §39
	if tab=="Workshop" then openTo("Workshop",station) elseif tab=="Journal" then openTo("Journal",if station=="Calendar" then "Calendar" elseif station=="Council" then "Council" elseif station=="Commissions" or station=="Museum" or station=="Motes" or station=="Factions" then station elseif station=="CollectionLog" then "Collection Log" else "Construction") else openTo("Hunt","Slayer") end
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
		UI.refreshSidebar() -- isle clock
	end
end)
updates.OnClientEvent:Connect(accept)
while not synced do
	send("state")
	if not synced then
		task.wait(2)
	end
end
