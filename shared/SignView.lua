-- Sign view rules (docs/DEPTH-CONTRACT.md §28, Signs v2). Pure functions used by
-- signs.client.lua (ReplicatedStorage.AetherSignView) and verify-signs.luau:
-- how big a floating sign draws at a distance, when it fades, how many are
-- visible at once, how it bobs and where a post arrow points on screen.
local View = {}

-- Caps: nearest N sign billboards are enabled (the rest are switched off).
View.CAP = {desktop = 18, phone = 8}
-- Scale clamp: full design size within REF studs, then shrinking with distance
-- (like a real plaque) but never below MIN (legible) or above MAX (never
-- covers the screen; phones draw smaller because their screens are).
View.REF = 22
View.SCALE = {desktop = {min = 0.5, max = 1}, phone = {min = 0.5, max = 0.78}}
-- Fade: opaque until FADE_START of the billboard's MaxDistance, gone at it.
View.FADE_START = 0.8
-- Bob: a slow float (studs, seconds); none with reduced motion.
View.BOB = {amplitude = 0.12, period = 4.6}
-- Update cadence: selection, scale, fade and arrows at 10 Hz; bob per frame
-- for enabled signs only; crystal glow every 2 s.
View.TICK, View.GLOW_TICK = 0.1, 2

function View.scaleFor(distance, phone)
	local band = if phone then View.SCALE.phone else View.SCALE.desktop
	distance = tonumber(distance) or 0
	if distance ~= distance or distance <= View.REF then return band.max end
	return math.clamp(band.max * View.REF / distance, band.min, band.max)
end

function View.fadeFor(distance, maxDistance)
	maxDistance = tonumber(maxDistance) or 100
	distance = tonumber(distance) or 0
	if distance ~= distance or maxDistance <= 0 then return 1 end
	local start = maxDistance * View.FADE_START
	if distance <= start then return 0 end
	return math.clamp((distance - start) / (maxDistance - start), 0, 1)
end

-- entries: {d = number, max = number, ...}; returns the nearest `cap` entries
-- within their own max distance (sorted near to far). `out` is reused.
local function nearer(a, b) return a.d < b.d end
function View.select(entries, cap, out)
	out = out or {}
	table.clear(out)
	for _, e in ipairs(entries) do
		if e.d == e.d and e.d <= (e.max or math.huge) then table.insert(out, e) end
	end
	table.sort(out, nearer)
	for i = #out, cap + 1, -1 do out[i] = nil end
	return out
end

function View.bob(t, phase, reduced)
	if reduced then return 0 end
	return View.BOB.amplitude * math.sin((tonumber(t) or 0) * 2 * math.pi / View.BOB.period + (tonumber(phase) or 0))
end

-- Arrow rotation (degrees, GUI convention: 0 points right, positive turns
-- clockwise) for a world direction seen from a camera: the destination's
-- bearing relative to where the camera looks, so "straight ahead" points up
-- the screen, "behind" points down and left / right point sideways.
function View.arrowRotation(direction, cameraCFrame)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then return -90 end
	local look = cameraCFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	if forward.Magnitude < 1e-3 then forward = Vector3.new(-cameraCFrame.UpVector.X, 0, -cameraCFrame.UpVector.Z) end
	forward = forward.Unit
	local right = Vector3.new(-forward.Z, 0, forward.X) -- forward turned 90° clockwise seen from above
	local d = flat.Unit
	return math.deg(math.atan2(-d:Dot(forward), d:Dot(right)))
end

-- Crystal glow transparency for a day factor (1 = noon, 0 = night).
function View.glowTransparency(dayFactor, day, night)
	local k = math.clamp(tonumber(dayFactor) or 1, 0, 1)
	return night + (day - night) * k
end

return View
