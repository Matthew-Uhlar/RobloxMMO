-- Device class (docs/DEPTH-CONTRACT.md §55 QC M3): the one phone / tablet rule
-- shared by forge.client.lua (mesh budgets, far LODs) and npc.client.lua
-- (dressed NPCs, outfit triangles per NPC, nameplates), so the outfit pool the
-- forge sizes and the dressed set npc.client.lua asks for always agree.
-- Touch-only devices (phones and tablets: touch, no keyboard) take the phone
-- budgets; anything with a keyboard is a desktop.
local Device = {}

-- uis: UserInputService (or a table with TouchEnabled / KeyboardEnabled).
function Device.isPhone(uis)
	if type(uis) ~= "table" and typeof(uis) ~= "Instance" then return false end
	local phone = false
	pcall(function() phone = uis.TouchEnabled == true and uis.KeyboardEnabled ~= true end)
	return phone
end

return Device
