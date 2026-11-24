-- Weather clock (ServerScriptService.Weather; docs/DEPTH-CONTRACT.md §50).
-- Cosmetic only: the ONE thing it does is keep workspace attribute
-- IsleWeather (shared/Ambience.lua A.encode) current. The schedule is a pure
-- function of server time (A.SLOT-second slots, a fixed integer hash per
-- region), so every server agrees, and every client on this server sees the
-- same weather; lightning strikes in storming regions are published as a
-- world event in the same attribute ("Region@serverTime"), which the lighting
-- director turns into a flash and the ambience layer into a bolt and a
-- thunder cue. No gameplay reads the weather: no damage, yield, XP or drop
-- changes, no parts, no remotes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local A = require(ReplicatedStorage:WaitForChild("AetherAmbience"))

local Weather = {last = nil, STEP = 0.5}
local function serverNow()
	local ok, t = pcall(function() return workspace:GetServerTimeNow() end)
	if ok and type(t) == "number" and t > 1e9 then return t end
	return os.time()
end
-- The attribute text for time t (the slot table plus the latest strike in
-- the last few seconds, so a late joiner never replays an old flash).
function Weather.textAt(t)
	local region, at = A.latestStrike(t, 3)
	return A.encode(A.slotAt(t), region, at)
end
function Weather.step()
	local text = Weather.textAt(serverNow())
	if text ~= Weather.last then
		Weather.last = text
		workspace:SetAttribute("IsleWeather", text)
	end
end
Weather.step()
task.spawn(function()
	while true do
		task.wait(Weather.STEP)
		local ok, err = pcall(Weather.step)
		if not ok then warn("[Weather] " .. tostring(err)) end
	end
end)
return Weather
