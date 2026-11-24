--!strict
-- Sign view rules (docs/DEPTH-CONTRACT.md §28, Signs v2). Pure functions used by
-- signs.client.lua (ReplicatedStorage.AetherSignView) and verify-signs.luau:
-- how big a floating sign draws at a distance (world-space feel, clamped per
-- archetype and device), when it drops to its compact title-only form, when it
-- fades, how many are visible, which overlapping plaques give way on screen,
-- how it bobs and where a post arrow points.
local View = {}

export type Band = {min: number, max: number}
export type Rect = {x0: number, y0: number, x1: number, y1: number}

-- Caps: nearest N sign billboards are enabled (the rest are switched off).
View.CAP = {desktop = 18, phone = 8}
-- Scale: REF / distance (a plaque shrinks like a real object), clamped per
-- archetype to a pixel band: MIN keeps the title legible far away, MAX stops a
-- close plaque covering the screen. Phones (viewport < PHONE_HEIGHT px tall)
-- draw in a tight 0.45-0.55 band: their screens are a third the height.
View.REF = 22
View.BAND = {
	desktop = {hanging = {min = .6, max = 1}, shop = {min = .6, max = 1}, plaque = {min = .6, max = 1},
		post = {min = .6, max = 1}, banner = {min = .55, max = .9}, ledger = {min = .6, max = 1}},
	phone = {hanging = {min = .45, max = .55}, shop = {min = .45, max = .55}, plaque = {min = .45, max = .55},
		post = {min = .45, max = .55}, banner = {min = .45, max = .5}, ledger = {min = .45, max = .55}},
}
View.PHONE_HEIGHT = 500
-- Below DETAIL scale a sign is compact: kicker and divider hidden (banners
-- swap to their short title-only pennant), so no text renders under MIN_TEXT px.
View.DETAIL = .7
View.MIN_TEXT = 10
-- UIScale and GroupTransparency are written in STEP increments, only on change.
View.STEP = .05
-- Fade: opaque until FADE_START of the billboard's MaxDistance, gone at it.
View.FADE_START = .8
-- Bob: a slow float (studs, seconds); none with reduced motion.
View.BOB = {amplitude = .12, period = 4.6}
-- Update cadence: selection, scale, fade, declutter and arrows at 10 Hz; bob
-- per frame for enabled signs only (skipped with reduced motion); glow every 2 s.
View.TICK, View.GLOW_TICK = .1, 2
-- Declutter: plaques whose on-screen boxes overlap (by more than MARGIN px)
-- give way to the nearer one.
View.MARGIN = 2

function View.quantise(x: number): number
	-- Divide by the step count (20) rather than multiply by 0.05: exact decimals.
	return math.floor(x / View.STEP + .5) / math.floor(1 / View.STEP + .5)
end

function View.isPhone(viewport: Vector2?): boolean
	return viewport ~= nil and viewport.Y > 0 and viewport.Y < View.PHONE_HEIGHT
end

function View.band(kind: string?, phone: boolean): Band
	local bands: {[string]: Band} = if phone then View.BAND.phone else View.BAND.desktop
	return bands[kind or "hanging"] or bands.hanging
end

-- Quantised UIScale for a sign `distance` studs away.
function View.scaleFor(distance: number?, phone: boolean, kind: string?): number
	local band = View.band(kind, phone)
	local d = tonumber(distance) or 0
	if d ~= d or d <= 0 then return band.max end
	return math.clamp(View.quantise(View.REF / d), band.min, band.max)
end

function View.compact(scale: number): boolean
	return scale < View.DETAIL - 1e-6
end

-- Quantised CanvasGroup transparency.
function View.fadeFor(distance: number?, maxDistance: number?): number
	local m = tonumber(maxDistance) or 100
	local d = tonumber(distance) or 0
	if d ~= d or m <= 0 then return 0 end
	local start = m * View.FADE_START
	if d <= start then return 0 end
	return View.quantise(math.clamp((d - start) / (m - start), 0, 1))
end

-- entries: {d = number, max = number, ...}; returns the nearest `cap` entries
-- within their own max distance (sorted near to far). `out` is reused.
local function nearer(a: any, b: any): boolean return a.d < b.d end
function View.select(entries: {any}, cap: number, out: {any}?): {any}
	local result: {any} = out or {}
	table.clear(result)
	for _, e in ipairs(entries) do
		if type(e.d) == "number" and e.d == e.d and e.d <= (e.max or math.huge) then table.insert(result, e) end
	end
	table.sort(result, nearer)
	for i = #result, cap + 1, -1 do result[i] = nil end
	return result
end

-- Screen box of a sign whose centre projects to (x, y): its visible size
-- (w, h at scale 1) offset `dy` px below the billboard centre, all scaled.
function View.rect(x: number, y: number, w: number, h: number, dy: number, scale: number): Rect
	local cy = y + dy * scale
	return {x0 = x - w * scale / 2, y0 = cy - h * scale / 2, x1 = x + w * scale / 2, y1 = cy + h * scale / 2}
end

function View.overlaps(a: Rect, b: Rect, margin: number?): boolean
	local m = margin or View.MARGIN
	return a.x0 < b.x1 - m and b.x0 < a.x1 - m and a.y0 < b.y1 - m and b.y0 < a.y1 - m
end

-- entries sorted near to far, each {rect = Rect?}; sets entry.clear = true for
-- the ones drawn (nil rect = off screen / behind the camera: not drawn, and
-- never hides another). Greedy: a sign is drawn unless a nearer drawn sign
-- overlaps it, so drawn boxes never overlap.
function View.declutter(entries: {any})
	for i, e in ipairs(entries) do
		local rect: Rect? = e.rect
		local clear = rect ~= nil
		if rect then
			for j = 1, i - 1 do
				local o = entries[j]
				if o.clear and View.overlaps(rect, o.rect) then clear = false; break end
			end
		end
		e.clear = clear
	end
end

-- Pin-hole projection (tests and previews; the client asks the camera):
-- screen x, y (px from the top left) and view depth of a world point for a
-- camera with vertical field of view `fov` (degrees) and viewport size.
function View.project(camera: CFrame, fov: number, viewport: Vector2, point: Vector3): (number, number, number)
	local rel = camera:PointToObjectSpace(point)
	local depth = -rel.Z
	if depth <= 1e-3 then return 0, 0, depth end
	local f = (viewport.Y / 2) / math.tan(math.rad(fov) / 2)
	return viewport.X / 2 + rel.X / depth * f, viewport.Y / 2 - rel.Y / depth * f, depth
end

function View.bob(t: number?, phase: number?, reduced: boolean?): number
	if reduced then return 0 end
	return View.BOB.amplitude * math.sin((tonumber(t) or 0) * 2 * math.pi / View.BOB.period + (tonumber(phase) or 0))
end

-- Arrow rotation (degrees, GUI convention: 0 points right, positive turns
-- clockwise) for a world direction seen from a camera: the destination's
-- bearing relative to where the camera looks, so "straight ahead" points up
-- the screen, "behind" points down and left / right point sideways.
function View.arrowRotation(direction: Vector3, cameraCFrame: CFrame): number
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
function View.glowTransparency(dayFactor: number?, day: number, night: number): number
	local k = math.clamp(tonumber(dayFactor) or 1, 0, 1)
	return night + (day - night) * k
end

return View
