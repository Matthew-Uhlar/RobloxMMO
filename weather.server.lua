-- Weather clock (ServerScriptService.Weather; docs/DEPTH-CONTRACT.md §50).
-- Cosmetic only: the ONE thing it does is keep workspace attribute
-- IsleWeather (shared/Ambience.lua A.encode) current. The schedule is a pure
-- function of server time (A.SLOT-second slots, a fixed integer hash per
-- region), so every server agrees, and every client on this server sees the
-- same weather. Lightning (QC H2) is not sent at all: every client computes
-- the strikes of a storming region from the same schedule (A.strikes) on
-- server time, so the flash, the bolt and the thunder cue land on the same
-- frame everywhere with no network latency. No gameplay reads the weather: no damage, yield, XP or drop
-- changes, no parts, no remotes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local A = require(ReplicatedStorage:WaitForChild("AetherAmbience"))

local Weather = {last = nil, STEP = 0.5}
local function serverNow()
	local ok, t = pcall(function() return workspace:GetServerTimeNow() end)
	if ok and type(t) == "number" and t > 1e9 then return t end
	return os.time()
end
-- The attribute text for time t: the slot's state per region (it changes
-- once per A.SLOT seconds).
function Weather.textAt(t)
	return A.encode(A.slotAt(t))
end
function Weather.step()
	local text = Weather.textAt(serverNow())
	if text ~= Weather.last then
		Weather.last = text
		workspace:SetAttribute("IsleWeather", text)
	end
end
do -- QC L8: a failing first step must not stop the loop below
	local ok, err = pcall(Weather.step)
	if not ok then warn("[Weather] " .. tostring(err)) end
end
task.spawn(function()
	while true do
		task.wait(Weather.STEP)
		local ok, err = pcall(Weather.step)
		if not ok then warn("[Weather] " .. tostring(err)) end
	end
end)
return Weather
