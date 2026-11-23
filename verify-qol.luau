-- QoL Depth (§41): the Lumen Lectern (daily Enchanting memory trials), the
-- Wardrobe, Vault Charters (bank tiers with a capped daily interest) and
-- Roost tethers (pet XP sharing) with the Roost keeper as Hub folk.
-- Part A checks the pure rules in shared/GameData.lua (Data.QoL): originality,
-- puzzle generators and answer checks, the daily XP ceiling, the item value a
-- day can pay, the charter cost curve (no coin mint), wardrobe validation,
-- tether slots and the townsfolk entry.
-- Part B runs world.server.lua with real Roblox instances: one lectern station
-- on the Aether Museum dais (Compass Quay) with its prompt and waypoint.
-- Part C runs server.server.lua with a deterministic clock and a DataStore
-- double: the lectern window, all three trials (reveal windows, answers,
-- misses, perfect runs, bonus reveals, timeouts, daily limits, a rejoin mid
-- trial, nothing secret in snapshots), the wardrobe (atomic swaps, fights,
-- cooldown, slots, missing items, accessory room, Ironman), vault interest
-- (once per UTC day, capped, never on first sight, charters), tethers and
-- migration of malformed records.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local function load(path, env)
	local source = fs.readFile(path):gsub("^\239\187\191", "")
	return luau.load(source, {debugName = path, environment = env or {}, injectGlobals = true})()
end
local Data = load("shared/GameData.lua")
local P = load("shared/Progression.lua", {script = nil})
P.useData(Data)
local Q = Data.QoL
local A, W, V, K = Q.Lectern, Q.Wardrobe, Q.Vault, Q.Tether
local checks = 0
local function eq(actual, expected, case)
	assert(actual == expected, case .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
	checks += 1
end
local function ok(cond, case) assert(cond, case); checks += 1 end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local X = Data.XP_TABLE
local function seeded(seed)
	local state = seed
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

------------------------------------------------------------------------------
-- Part A: data and pure rules.
------------------------------------------------------------------------------
local partA = checks
ok(type(Q) == "table" and A and W and V and K, "Data.QoL sections")
-- A1. Originality.
do
	local banned = {"hypixel", "skyblock", "experimentation", "superpair", "chronomatron", "ultrasequencer", "kat ", "kat,", "melody", "bits", "booster cookie", "runescape"}
	local texts = {A.NAME}
	for _, g in pairs(A.Games) do table.insert(texts, g.name .. " " .. g.text) end
	for _, t in ipairs(A.Tiers) do table.insert(texts, t.id) end
	for _, t in ipairs(V.Tiers) do table.insert(texts, t.name) end
	local npc = Data.Townsfolk.NPCs[Q.ROOST_KEEPER]
	ok(npc ~= nil and npc.anchorOnly and table.find(Data.Townsfolk.RegionFolkOrder, Q.ROOST_KEEPER) and Data.RegionArt.FolkByRole[Q.ROOST_KEEPER].region == "Hub", "the Roost keeper is Hub folk")
	eq(npc.name .. ", " .. npc.title, Data.PetDepth.KEEPER, "the keeper's name matches the Roost UI")
	for _, node in pairs(npc.nodes) do
		table.insert(texts, node.text)
		for _, o in ipairs(node.options) do
			table.insert(texts, o.label)
			if o.atlas then ok(Data.Townsfolk.AtlasStations[o.atlas] ~= nil, "keeper atlas option " .. o.atlas) end
		end
	end
	ok(Data.Townsfolk.AtlasStations.Lectern ~= nil and Data.Townsfolk.AtlasStations.Roost ~= nil, "atlas stations registered")
	for _, text in ipairs(texts) do
		for _, word in ipairs(banned) do ok(not string.find(string.lower(text), word, 1, true), "original: " .. string.sub(text, 1, 40)) end
	end
end
-- A2. Tiers: gates rise, puzzles fit their grids and glyph sets.
do
	eq(#A.Tiers, 6, "six lectern tiers")
	eq(#A.CELL_CHARS, 25, "25 cell characters")
	eq(#A.GLYPHS, 9, "nine glyphs")
	for i, t in ipairs(A.Tiers) do
		if i > 1 then
			ok(t.level > A.Tiers[i - 1].level and t.xp > A.Tiers[i - 1].xp and t.seqRounds >= A.Tiers[i - 1].seqRounds, t.id .. " is harder and pays more")
		end
		ok(t.glyphs <= #A.GLYPHS and t.cells <= 25 and t.pairs <= #A.GLYPHS, t.id .. " fits its glyphs and grid")
		ok(A.recallCount(t, t.recallRounds) <= t.cells, t.id .. " last recall round fits the grid")
		ok(t.seqRounds <= 15 and A.recallCount(t, t.recallRounds) <= 25, t.id .. " answers fit the 25-char bound")
		eq(A.bestTier(t.level), i, t.id .. " opens at Enchanting " .. t.level)
		if i > 1 then eq(A.bestTier(t.level - 1), i - 1, t.id .. " closed one level below") end
	end
	eq(A.Tiers[1].level, 1, "Apprentice opens at level 1")
	eq(A.roundXp(A.Tiers[1], 1), A.Tiers[1].xp, "round 1 pays the tier XP")
	eq(A.roundXp(A.Tiers[3], 6), math.floor(A.Tiers[3].xp * 2 + 0.5), "round 6 pays double")
end
-- A3. Generators and answers.
do
	local rng = seeded(41)
	for _, t in ipairs(A.Tiers) do
		for _ = 1, 30 do
			local seq = A.makeSequence(t, rng)
			eq(#seq, t.seqRounds, t.id .. " sequence length")
			for _, g in ipairs(seq) do ok(g >= 1 and g <= t.glyphs and g % 1 == 0, t.id .. " glyph in range") end
			local r = math.random(1, t.seqRounds)
			local answer = ""
			for i = 1, r do answer ..= tostring(seq[i]) end
			ok(A.checkSequence(seq, r, answer), "sequence prefix accepted")
			ok(not A.checkSequence(seq, r, answer .. "1"), "too long refused")
			ok(not A.checkSequence(seq, r, string.sub(answer, 1, -2)), "too short refused")
			local wrong = string.sub(answer, 1, -2) .. tostring(seq[r] % t.glyphs + 1)
			ok(not A.checkSequence(seq, r, wrong), "a wrong last glyph refused")
			ok(not A.checkSequence(seq, 1, "0") and not A.checkSequence(seq, 1, "a") and not A.checkSequence(seq, 1, nil), "malformed sequence answers refused")
			local rr = math.random(1, t.recallRounds)
			local cells = A.makeRecall(t, rr, rng)
			eq(#cells, A.recallCount(t, rr), t.id .. " recall count")
			local seen, enc = {}, ""
			for _, c in ipairs(cells) do
				ok(c >= 1 and c <= t.cells and not seen[c], t.id .. " distinct cells in the grid")
				seen[c] = true
				enc ..= A.cellChar(c)
			end
			ok(A.checkRecall(cells, enc), "recall order accepted")
			if #cells > 1 then ok(not A.checkRecall(cells, string.reverse(enc)), "reversed order refused") end
			ok(not A.checkRecall(cells, enc .. "1") and not A.checkRecall(cells, "") and not A.checkRecall(cells, nil), "malformed recall answers refused")
			local cards, rewards = A.makeBoard(t, rng)
			eq(#cards, 2 * t.pairs, t.id .. " board size")
			eq(#rewards, t.pairs, t.id .. " one reward per pair")
			local per, kinds = {}, {}
			for _, c in ipairs(cards) do per[c.p] = (per[c.p] or 0) + 1 end
			for p = 1, t.pairs do eq(per[p], 2, "pair " .. p .. " appears twice") end
			for _, rw in ipairs(rewards) do
				kinds[rw.id or rw.k] = (kinds[rw.id or rw.k] or 0) + 1
				if rw.k == "item" then ok(Data.Items[rw.id] ~= nil, "reward item exists") end
			end
			eq(kinds.reveal, 1, "one reveal card")
			ok((kinds.TemperingTome or 0) <= (if t.tome then 1 else 0) and (kinds.MasterworkTome or 0) <= (if t.masterwork then 1 else 0), t.id .. " tomes only where the tier offers them")
		end
	end
	for c = 1, 25 do eq(A.charCell(A.cellChar(c)), c, "cell char round trip " .. c) end
	eq(A.charCell("z"), nil, "unknown cell char")
	-- Daily records roll forward only.
	local rec = {day = 500, used = {seq = 2}, bonus = 3}
	ok(not A.roll(rec, 499) and rec.used.seq == 2 and rec.bonus == 3, "a clock behind never re-opens the day")
	ok(not A.roll(rec, 500), "same day keeps the attempts")
	ok(A.roll(rec, 501) and next(rec.used) == nil and rec.bonus == 0, "a new UTC day resets attempts and bonus")
	eq(A.left(rec, "seq"), A.Games.seq.attempts, "fresh attempts")
	eq(A.bonusFor("seq", 7, A.Tiers[2]), 2, "seq: one bonus per 3 rounds")
	eq(A.bonusFor("seq", A.Tiers[2].seqRounds, A.Tiers[2]), A.Tiers[2].seqRounds // 3 + 1, "a perfect run adds one")
	eq(A.bonusFor("recall", 5, A.Tiers[3]), 2, "recall: one bonus per 2 rounds")
	eq(A.reveals(A.Tiers[1], 99), A.baseReveals(A.Tiers[1]) + math.min(A.BONUS_CAP, A.Tiers[1].pairs), "bonus reveals capped")
end
-- A4. Balance: a perfect day stays well inside normal Enchanting progress and pays little coin value.
do
	for _, t in ipairs(A.Tiers) do
		local lv = t.level
		local ten = X[math.min(99, lv + 10)] - X[lv]
		local max = A.dailyMaxXp(t)
		ok(max <= ten, t.id .. " perfect day (" .. max .. " XP) below ten levels from its gate (" .. ten .. ")")
		if lv >= 50 then ok(max <= 0.35 * ten, t.id .. " perfect day is a small share of the high levels") end
		-- Coin value of a board (everything matched, both tomes): bounded per day.
		local value = t.dust * Data.Items.ArcaneDust.value * math.ceil(t.pairs / 2)
		if t.tome then value += Data.Items.TemperingTome.value end
		if t.masterwork then value += Data.Items.MasterworkTome.value * t.masterwork end
		ok(value <= 6000, t.id .. " expected item value per day " .. math.floor(value) .. " coins")
	end
end
-- A5. Vault Charters: rising rate and capacity; every charter takes >= 30 days of its extra ceiling to repay.
do
	for i, t in ipairs(V.Tiers) do
		ok(V.maxDaily(t) == math.floor(t.cap * t.rate), t.id .. " ceiling")
		eq(V.interest(t, t.cap * 50), V.maxDaily(t), t.id .. " interest capped at the ceiling")
		eq(V.interest(t, -5), 0, "negative balance pays nothing")
		eq(V.interest(t, 0 / 0), 0, "NaN balance pays nothing")
		if i > 1 then
			local prev = V.Tiers[i - 1]
			ok(t.rate > prev.rate and t.cap > prev.cap, t.id .. " improves on " .. prev.id)
			local extra = V.maxDaily(t) - V.maxDaily(prev)
			ok(t.cost / extra >= 30, t.id .. " repays in " .. math.floor(t.cost / extra) .. " days (>= 30)")
			for id, tier in pairs(t.needs) do ok(table.find(Data.CollectionItems, id) and tier >= 1 and tier <= 9, t.id .. " needs a real collection " .. id) end
		end
	end
	ok(V.maxDaily(V.Tiers[#V.Tiers]) <= 100000, "top charter pays at most 100k a day")
	local rec = {tier = 1}
	eq(V.roll(rec, 900, 50000), 0, "a new charter starts counting tomorrow")
	eq(V.roll(rec, 900, 50000), 0, "nothing twice on the same day")
	eq(V.roll(rec, 901, 50000), 50, "next day pays 0.1% of 50k")
	eq(V.roll(rec, 901, 50000), 0, "once per day")
	eq(V.roll(rec, 899, 50000), 0, "a clock behind pays nothing")
	eq(rec.day, 901, "the day never rolls back")
	eq(V.roll(rec, 950, 9e9), V.maxDaily(V.Tiers[1]), "a long absence pays one capped day, never a backlog")
end
-- A6. Wardrobe rules.
do
	eq(W.slotsFor(1), 3, "three loadouts at the start")
	eq(W.slotsFor(15), 5, "five at Combat 15")
	eq(W.slotsFor(30), 7, "seven at Combat 30")
	eq(W.slotsFor(99), 9, "nine at most")
	local helm, chest, boots, gated
	for id, d in pairs(Data.Items) do
		if not d.requires then
			if d.slot == "helmet" and (not helm or id < helm) then helm = id end
			if d.slot == "chest" and (not chest or id < chest) then chest = id end
			if d.slot == "boots" and (not boots or id < boots) then boots = id end
		elseif d.slot == "helmet" and d.requires.Combat and d.requires.Combat >= 20 and (not gated or id < gated) then gated = id end
	end
	ok(helm and chest and boots and gated, "test armour found")
	local accs = {}
	for id, d in pairs(Data.Items) do if d.kind == "accessory" then table.insert(accs, id) end end
	table.sort(accs)
	local set = W.capture({weapon = "Blade", helmet = helm, chest = chest}, {accs[1], accs[2]})
	eq(set.weapon, nil, "the weapon is never captured")
	eq(set.helmet, helm, "helmet captured")
	eq(#set.acc, 2, "accessories captured")
	local dirty = {helmet = chest, chest = chest, legs = "Nope", acc = {accs[1], accs[1], "Ore", 7}}
	local clean = W.clean(dirty)
	ok(clean.helmet == nil and clean.chest == chest and clean.legs == nil and #clean.acc == 1, "clean drops mis-slotted, unknown and duplicate entries")
	eq(W.clean({acc = {"Ore"}}), nil, "an empty set cleans to nil")
	eq(W.clean("x"), nil, "garbage cleans to nil")
	local items = {[helm] = 1, [chest] = 1, [accs[1]] = 1, [accs[2]] = 1}
	local yes = function() return true end
	ok(W.check(set, items, 5, yes), "an owned set fits")
	local okA, whyA = W.check(set, {[helm] = 1, [accs[1]] = 1, [accs[2]] = 1}, 5, yes)
	ok(not okA and has(whyA, "no longer own"), "a sold piece refuses the whole set")
	local okB, whyB = W.check(set, items, 1, yes)
	ok(not okB and has(whyB, "accessory slots"), "too few accessory slots refused")
	local okC, whyC = W.check({helmet = gated, acc = {}}, {[gated] = 1}, 5, function() return false, "Combat 40" end)
	ok(not okC and has(whyC, "requires Combat 40"), "requirements checked")
	local okD = W.check({acc = {accs[1], accs[1]}}, items, 5, yes)
	ok(not okD, "duplicate accessory refused")
	ok(not W.check(nil, items, 5, yes), "an empty slot refused")
	Q.testArmour = {helm = helm, chest = chest, boots = boots, gated = gated, accs = accs}
end
-- A7. Tethers.
do
	eq(K.slotsFor(9), 0, "no tether below Taming 10")
	eq(K.slotsFor(10), 1, "one tether at Taming 10")
	eq(K.slotsFor(25), 2, "two at 25")
	eq(K.slotsFor(99), 3, "three at most")
	eq(K.activeXpFor(150), 1500, "preview: 10% share needs 10x")
	eq(K.activeXpFor(-3), 0, "preview never negative")
	ok(Q.dayOf(86400 * 3 + 5) == 3 and Q.dayOf(nil) == 0, "UTC day index")
	eq(Q.whole(0 / 0), nil, "NaN is not whole")
	eq(Q.whole(math.huge), nil, "inf is not whole")
end
print("PASS: " .. (checks - partA) .. " QoL data assertions.")

------------------------------------------------------------------------------
-- Part B: the lectern station on the Aether Museum dais.
------------------------------------------------------------------------------
local partB = checks
local function signal()
	local listeners = {}
	return {
		Connect = function(_, f)
			local c = {Connected = true}
			function c:Disconnect() self.Connected = false end
			table.insert(listeners, {f, c})
			return c
		end,
		Fire = function(_, ...) for _, l in listeners do if l[2].Connected then l[1](...) end end end,
	}
end
local promptSignals = {}
roblox.implementProperty("ProximityPrompt", "Triggered", function(prompt)
	if not promptSignals[prompt] then promptSignals[prompt] = signal() end
	return promptSignals[prompt]
end)
do
	local world = roblox.Instance.new("Workspace")
	local dataModule = {Name = "AetherData"}
	local worldEnv = {
		game = {GetService = function(_, name)
			if name == "Players" then return {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end} end
			if name == "Lighting" then return roblox.Instance.new("Lighting") end
			if name == "CollectionService" then return {AddTag = function() end} end
			if name == "ReplicatedStorage" then return {WaitForChild = function(_, n) return if n == "AetherData" then dataModule else nil end} end
			if name == "ServerStorage" then return {FindFirstChild = function() return nil end} end
			return {}
		end},
		workspace = world, Instance = roblox.Instance, Vector3 = Vector3, Vector2 = roblox.Vector2, CFrame = CFrame, Color3 = roblox.Color3,
		UDim2 = roblox.UDim2, Font = roblox.Font, Enum = roblox.Enum, NumberRange = roblox.NumberRange, NumberSequence = roblox.NumberSequence, ColorSequence = roblox.ColorSequence,
		task = {spawn = function() end, wait = function() end},
		require = function(module) assert(module == dataModule, "world requires only AetherData") return Data end,
	}
	local worldSource = fs.readFile("world.server.lua"):gsub("plans%.Position", "plans.CFrame.Position")
	luau.load(worldSource, {environment = worldEnv, injectGlobals = true})()
	local islands = world:FindFirstChild("Islands")
	local hub = islands:FindFirstChild("Compass Quay")
	local museum = hub:FindFirstChild("Aether Museum", true)
	ok(museum ~= nil, "the Aether Museum stands on Compass Quay")
	local found = {}
	for _, q in islands:GetDescendants() do
		if q:IsA("ProximityPrompt") and q:GetAttribute("IsleAction") == "lecternVisit" then table.insert(found, q) end
	end
	eq(#found, 1, "exactly one lectern prompt")
	local q = found[1]
	ok(q:IsDescendantOf(hub) and not q:IsDescendantOf(museum) and q.Parent.Parent:GetAttribute("LecternContent") == true, "the lectern is its own model on Compass Quay")
	local stand = q.Parent
	ok(stand:IsA("BasePart") and stand.Anchored and stand:GetAttribute("Shape") == "Workbench", "a mesh-slot station prop")
	eq(stand.Material == roblox.Enum.Material.Neon, false, "no Neon")
	ok(math.abs(q.HoldDuration - 0.36) < 1e-6 and q.MaxActivationDistance == 9, "interact hold prompt")
	local dais = museum:FindFirstChild("Museum dais")
	local local_ = dais.CFrame:PointToObjectSpace(stand.CFrame.Position)
	ok(math.abs(local_.X) <= 8 - stand.Size.X / 2 and math.abs(local_.Z) <= 6 - stand.Size.Z / 2, "the lectern stands on the dais")
	ok(math.abs((stand.CFrame.Position.Y - stand.Size.Y / 2) - (dais.CFrame.Position.Y + dais.Size.Y / 2)) < 0.05, "resting on the dais top")
	-- Clear of the museum's other props (case, log lectern, statue).
	for _, other in ipairs(museum:GetDescendants()) do
		if other:IsA("BasePart") and other ~= stand and other ~= dais and other.Transparency < 1 and other.Name ~= "Museum lintel" then
			local d = Vector3.new(other.CFrame.Position.X - stand.CFrame.Position.X, 0, other.CFrame.Position.Z - stand.CFrame.Position.Z).Magnitude
			ok(d >= 2.2, "clear of " .. other.Name .. " (" .. string.format("%.1f", d) .. ")")
		end
	end
	ok(hub:FindFirstChild("Anchor_Waypoint_Lectern", true) ~= nil, "lectern waypoint anchor")
	local lights = 0
	for _, o in museum:GetDescendants() do if o:IsA("Light") then lights += 1 end end
	eq(lights, 0, "no new lights in the museum")
end
print("PASS: " .. (checks - partB) .. " QoL world assertions.")

------------------------------------------------------------------------------
-- Part C: server behaviour.
------------------------------------------------------------------------------
local partC = checks
local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in value do out[k] = copy(v) end
	return out
end
local DAY = Q.DAY
local clock, utc = 10, DAY * 20500 + 3600
local function advance(seconds) clock += seconds; utc += seconds end
local data = {}
local db = {}
function db:GetAsync(key) return copy(data[key]) end
function db:UpdateAsync(key, op)
	local value = op(copy(data[key]))
	if value ~= nil then data[key] = copy(value) end
	return copy(data[key])
end
local markers = {AetherData = {Name = "AetherData"}, AetherProgression = {Name = "AetherProgression"}}
local modules = {[markers.AetherData] = Data, [markers.AetherProgression] = P}
local rollSeq, rollAt = {0.13, 0.71, 0.42, 0.88, 0.05, 0.57, 0.29, 0.94, 0.36, 0.63, 0.17, 0.81, 0.49, 0.02, 0.74}, 0
local function nextRoll() rollAt = rollAt % #rollSeq + 1 return rollSeq[rollAt] end
local services = {
	Players = {PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end},
	ProximityPromptService = {PromptTriggered = signal()},
	ReplicatedStorage = {WaitForChild = function(_, name) return assert(markers[name], name) end}, ServerStorage = {FindFirstChild = function() return nil end},
	DataStoreService = {GetDataStore = function() return db end},
	HttpService = {GenerateGUID = function() return "qol-test" end},
	RunService = {IsStudio = function() return false end},
}
local fakeWorkspace = {attrs = {}}
function fakeWorkspace:GetAttribute(key) return self.attrs[key] end
function fakeWorkspace:SetAttribute(key, value) self.attrs[key] = value end
function fakeWorkspace:FindFirstChild() return nil end
function fakeWorkspace:Raycast() return nil end
local coroutines, yieldOf = {}, {}
local serverObjects = {}
local env = {
	game = {GetService = function(_, name) return services[name] end, BindToClose = function() end},
	workspace = fakeWorkspace, Vector3 = Vector3, CFrame = CFrame,
	Instance = {new = function()
		local o = {Event = signal(), FireClient = function(_, player, state) player.last = state; player.pushes = (player.pushes or 0) + 1 end}
		table.insert(serverObjects, o)
		return o
	end},
	os = {clock = function() return clock end, time = function() return math.floor(utc) end},
	require = function(target) return assert(modules[target], "unexpected require") end,
	Random = {new = function() return {NextNumber = function() return nextRoll() end, NextInteger = function(_, lo) return lo end} end},
	task = {
		spawn = function(f, ...)
			local co = coroutine.create(f)
			local okRun, err = coroutine.resume(co, ...)
			assert(okRun, err)
			if coroutine.status(co) == "suspended" then table.insert(coroutines, co) end
			return co
		end,
		defer = function(f, ...) f(...) end,
		wait = function(t) yieldOf[coroutine.running()] = t; return coroutine.yield(t) end,
		delay = function() end,
	},
}
local serverSource = fs.readFile("server.server.lua"):gsub("^\239\187\191", ""):gsub("base%.Position", "base.CFrame.Position")
luau.load(serverSource, {environment = env, injectGlobals = true})()
local saver
for _, co in ipairs(coroutines) do if yieldOf[co] == 55 then saver = co end end
ok(saver ~= nil, "autosave loop found")
local remote, bridge
for _, o in ipairs(serverObjects) do
	if o.OnServerInvoke then remote = o end
	if o.Name == "IsleBridge" then bridge = o end
end
ok(remote ~= nil and bridge ~= nil, "IsleAction and IsleBridge found")
local function renew() assert(coroutine.resume(saver, 55)) end
local function player(id)
	local humanoid = {Health = 100, MaxHealth = 100, WalkSpeed = 16, Died = signal(), TakeDamage = function(self, n) self.Health -= n end}
	local root = {Position = Vector3.new(0, 10, 0), Anchored = false, AssemblyLinearVelocity = Vector3.zero}
	local p = {UserId = id, Name = "Scholar" .. id, Parent = true, CharacterAdded = signal(), Kick = function(self, why) self.kicked = why end, attrs = {}}
	function p:GetAttribute(key) return self.attrs[key] end
	function p:SetAttribute(key, value) self.attrs[key] = value end
	p.Character = {Parent = true, FindFirstChild = function() return root end, FindFirstChildOfClass = function() return humanoid end,
		WaitForChild = function() return humanoid end, PivotTo = function(_, cf) root.Position = cf.Position end}
	p.root, p.humanoid = root, humanoid
	services.Players.PlayerAdded:Fire(p)
	return p
end
local online = {}
local function leave(p) services.Players.PlayerRemoving:Fire(p); if online[p.UserId] == p then online[p.UserId] = nil end end
local function join(id, mutate)
	if online[id] then leave(online[id]) end
	if not data["p" .. id] then leave(player(id)) end
	if mutate then mutate(data["p" .. id].profile) end
	online[id] = player(id)
	return online[id]
end
local function cmd(p, verb, item)
	advance(1)
	renew()
	return remote.OnServerInvoke(p, verb, item)
end
local function saved(id) renew(); return data["p" .. id].profile end
local function visit(p)
	advance(1)
	renew()
	local q = {Enabled = true, MaxActivationDistance = 9, attrs = {IsleAction = "lecternVisit"}}
	function q:GetAttribute(k) return self.attrs[k] end
	local base = {Position = p.root.Position, CFrame = CFrame.new(p.root.Position)}
	function q:FindFirstAncestorWhichIsA() return base end
	p.last = nil
	services.ProximityPromptService.PromptTriggered:Fire(q, p)
	return p.last
end
-- Deep scan: a snapshot never carries a secret key.
local function leaks(value, depth)
	depth = depth or 0
	if type(value) ~= "table" or depth > 6 then return false end
	for k, v in pairs(value) do
		if k == "seq" or k == "cells" or k == "cards" or k == "rw" then return true end
		if leaks(v, depth + 1) then return true end
	end
	return false
end

-- C1. The window: a world prompt opens it; the remote alone cannot.
local s1 = join(8101, function(pr) pr.xp.Enchanting = X[32]; pr.started = true end)
local st = cmd(s1, "state")
ok(type(st.qol) == "table" and type(st.qol.lectern) == "table" and st.qol.lectern.tier == 3, "snapshot carries the lectern (Scholar at Enchanting 32)")
eq(st.qol.lectern.left.seq, A.Games.seq.attempts, "fresh attempts")
ok(has(cmd(s1, "lecternStart", "seq:1").message, "Touch the Lumen Lectern"), "no trial without touching the lectern")
ok(has(cmd(s1, "lecternVisit").message, "Touch the Lumen Lectern"), "the visit needs the world prompt")
local v1 = visit(s1)
ok(has(v1.message, "hums awake"), "lectern prompt answers")
eq(s1.attrs.IsleStation, "Lectern", "the atlas opens Hero › Lectern")
ok((s1.attrs.LecternUntil or 0) >= utc + A.VISIT_SECONDS - 2, "a 10-minute window")
ok(has(cmd(s1, "lecternStart", "seq:4").message, "require Enchanting 50"), "tier gate")
ok(has(cmd(s1, "lecternStart", "seq:9").message, "Choose a trial"), "unknown tier")
ok(has(cmd(s1, "lecternStart", "bogus:1").message, "Choose a trial"), "unknown game")
ok(has(cmd(s1, "lecternAnswer", "1").message, "No trial"), "no answer without a trial")
-- C2. Glyph Sequence at Scholar: the reveal, right answers, then a miss.
local t3 = A.Tiers[3]
local xp0 = cmd(s1, "state").xp.Enchanting
local r1 = cmd(s1, "lecternStart", "seq:3")
ok(has(r1.message, "Glyph Sequence begins"), "trial starts")
local sess = r1.qol.lectern.session
ok(sess and sess.g == "seq" and sess.r == 1 and sess.showing == true and #sess.show == 1, "round 1 shows one glyph")
ok(not leaks(r1.qol.lectern.session), "the snapshot holds no hidden sequence")
eq(r1.qol.lectern.left.seq, A.Games.seq.attempts - 1, "an attempt is spent at the start")
local secret = saved(8101).lectern.s
ok(secret and #secret.seq == t3.seqRounds, "the server keeps the full sequence")
eq(sess.show[1], secret.seq[1], "the reveal matches round 1")
local function seqAnswer(s, r) local a = "" for i = 1, r do a ..= tostring(s.seq[i]) end return a end
local r2 = cmd(s1, "lecternAnswer", seqAnswer(secret, 1))
ok(has(r2.message, "Round 1 cleared"), "round 1 cleared")
eq(r2.xp.Enchanting, xp0 + A.roundXp(t3, 1), "round 1 pays its XP")
ok(#r2.qol.lectern.session.show == 2, "round 2 shows two glyphs")
-- After the reveal window the glyphs are gone from snapshots.
advance(A.revealSeconds("seq", 2) + 2)
local hidden = cmd(s1, "state").qol.lectern.session
ok(hidden.showing == false and hidden.show == nil, "glyphs hidden after the reveal")
local r3 = cmd(s1, "lecternAnswer", seqAnswer(secret, 2))
ok(has(r3.message, "Round 2 cleared"), "round 2 cleared from memory")
local wrong = seqAnswer(secret, 3)
wrong = string.sub(wrong, 1, 2) .. tostring(secret.seq[3] % t3.glyphs + 1)
local r4 = cmd(s1, "lecternAnswer", wrong)
ok(has(r4.message, "round 3 missed"), "a miss ends the trial")
eq(r4.qol.lectern.session, nil, "session closed")
eq(r4.xp.Enchanting, xp0 + A.roundXp(t3, 1) + A.roundXp(t3, 2), "a miss pays nothing more")
eq(r4.qol.lectern.bonus, A.bonusFor("seq", 2, t3), "two rounds bank no bonus")
eq(r4.qol.lectern.best.seq, 2, "best recorded")
ok(has(cmd(s1, "lecternAnswer", seqAnswer(secret, 3)).message, "No trial"), "answers after the end are refused")
-- C3. A perfect second run banks the bonus; a third start is refused.
cmd(s1, "lecternStart", "seq:3")
local sec2 = saved(8101).lectern.s
local xpA = cmd(s1, "state").xp.Enchanting
local last
for r = 1, t3.seqRounds do last = cmd(s1, "lecternAnswer", seqAnswer(sec2, r)) end
ok(has(last.message, "Perfect Glyph Sequence"), "a perfect run")
local expectXp = 0
for r = 1, t3.seqRounds do expectXp += A.roundXp(t3, r) end
eq(last.xp.Enchanting, xpA + expectXp, "every round paid once")
eq(last.qol.lectern.bonus, A.bonusFor("seq", t3.seqRounds, t3), "perfect bonus banked")
ok(has(cmd(s1, "lecternStart", "seq:3").message, "No Glyph Sequence attempts left"), "daily limit")
-- C4. Starfall Recall: right order, then a timeout.
local rc = cmd(s1, "lecternStart", "recall:3")
local rs = rc.qol.lectern.session
ok(rs.g == "recall" and rs.cols == t3.grid[1] and rs.rows == t3.grid[2] and #rs.show == t3.recallStart, "recall reveal shows the first stars")
ok(not leaks(rc.qol.lectern.session), "recall snapshot holds no hidden layout")
local secR = saved(8101).lectern.s
local function enc(cells) local a = "" for _, c in ipairs(cells) do a ..= A.cellChar(c) end return a end
ok(has(cmd(s1, "lecternAnswer", string.rep("z", 25)).message, "missed"), "a garbage recall answer is a miss")
cmd(s1, "lecternStart", "recall:3")
secR = saved(8101).lectern.s
local ra = cmd(s1, "lecternAnswer", enc(secR.cells))
ok(has(ra.message, "Round 1 cleared") and #ra.qol.lectern.session.show == t3.recallStart + 1, "recall round 2 adds a star")
local before = ra.qol.lectern.bonus
advance(A.ANSWER_SECONDS + 30)
local timed = cmd(s1, "state")
eq(timed.qol.lectern.session, nil, "a stalled trial times out")
ok(has(timed.message, "timed out"), "timeout explained")
eq(timed.qol.lectern.bonus, math.min(A.BONUS_CAP, before + A.bonusFor("recall", 1, t3)), "timeout keeps what was earned")
eq(timed.qol.lectern.left.recall, 0, "both recall attempts used")
-- C5. Mirror Pairs: reveals, a miss, matches pay once, turned cards only.
local bonus = timed.qol.lectern.bonus
local pz = cmd(s1, "lecternStart", "pairs:3")
local ps = pz.qol.lectern.session
eq(ps.left, A.reveals(t3, bonus), "reveals = base + bonus")
eq(pz.qol.lectern.bonus, 0, "the day's bonus went into the board")
ok(not leaks(pz.qol.lectern.session) and next(ps.face) == nil, "no card face before turning")
local board = saved(8101).lectern.s
local function partner(i) for j, c in ipairs(board.cards) do if j ~= i and c.p == board.cards[i].p then return j end end end
local function notPartner(i) for j, c in ipairs(board.cards) do if c.p ~= board.cards[i].p then return j end end end
ok(has(cmd(s1, "lecternFlip", "0").message, "Choose a card"), "card 0 refused")
ok(has(cmd(s1, "lecternFlip", "1.5").message, "Choose a card"), "fractional card refused")
ok(has(cmd(s1, "lecternFlip", "99").message, "Choose a card"), "card past the board refused")
local f1 = cmd(s1, "lecternFlip", "1")
local face1 = f1.qol.lectern.session.face["1"]
ok(face1 and face1.g == board.cards[1].g and f1.qol.lectern.session.left == ps.left - 1, "a turned card shows its glyph")
local count = 0
for _ in pairs(f1.qol.lectern.session.face) do count += 1 end
eq(count, 1, "only the turned card is visible")
ok(has(cmd(s1, "lecternFlip", "1").message, "already turned"), "the same card twice refused")
local miss = notPartner(1)
local f2 = cmd(s1, "lecternFlip", tostring(miss))
ok(has(f2.message, "No match") and f2.qol.lectern.session.face["1"].miss and f2.qol.lectern.session.face[tostring(miss)].miss, "a miss shows both cards once")
local f3 = cmd(s1, "lecternFlip", tostring(miss))
ok(f3.qol.lectern.session.face["1"] == nil, "missed cards turn back over")
ok(has(cmd(s1, "lecternFlip", "1").message, "No match"), "a second miss")
-- Match card 1 and its partner.
cmd(s1, "lecternFlip", "1")
local preState = cmd(s1, "state")
local pre = {xp = {Enchanting = preState.xp.Enchanting}, items = table.clone(preState.items), qol = {lectern = {session = {left = preState.qol.lectern.session.left}}}}
local p1 = partner(1)
local rw = board.rw[board.cards[1].p]
local f4 = cmd(s1, "lecternFlip", tostring(p1))
ok(has(f4.message, "Matched"), "a matched pair")
if rw.k == "xp" then eq(f4.xp.Enchanting, pre.xp.Enchanting + rw.n, "XP card pays once")
elseif rw.k == "item" then eq((f4.items[rw.id] or 0), (pre.items[rw.id] or 0) + rw.n, "item card pays once")
else eq(f4.qol.lectern.session.left, pre.qol.lectern.session.left - 1 + rw.n, "reveal card adds reveals") end
ok(f4.qol.lectern.session.face["1"].m and f4.qol.lectern.session.face["1"].rw ~= nil, "matched cards stay face up with their reward")
ok(has(cmd(s1, "lecternFlip", tostring(p1)).message, "already matched"), "a matched card cannot pay twice")
-- Rejoin mid-board: the board is saved with the journal.
s1 = join(8101)
local back = cmd(s1, "state")
ok(back.qol.lectern.session and back.qol.lectern.session.g == "pairs" and back.qol.lectern.session.face["1"].m, "the board survives a rejoin")
-- Match everything else (perfect memory) until the board ends.
local guard = 0
while true do
	guard += 1
	assert(guard < 60, "board ends")
	local cur = saved(8101).lectern.s
	if not cur then break end
	local i
	for k = 1, #cur.cards do if not table.find(cur.m, k) then i = k break end end
	local a = cmd(s1, "lecternFlip", tostring(i))
	if not a.qol.lectern.session then break end
	local b = cmd(s1, "lecternFlip", tostring(partner(i)))
	if not b.qol.lectern.session then ok(has(b.message, "Every pair matched") or has(b.message, "spent"), "board ends with a reason") break end
end
ok(saved(8101).lectern.best.pairs >= 1, "pairs best recorded")
visit(s1)
ok(has(cmd(s1, "lecternStart", "pairs:3").message, "No Mirror Pairs attempts"), "one board a day")
-- C6. A new UTC day renews the attempts (and the lectern window still applies).
utc = (Q.dayOf(utc) + 1) * DAY + 30
local nd = cmd(s1, "state")
ok(nd.qol.lectern.left.seq == A.Games.seq.attempts and nd.qol.lectern.left.pairs == 1 and nd.qol.lectern.bonus == 0, "attempts renew at the UTC day")
ok(has(cmd(s1, "lecternStart", "seq:1").message, "Touch the Lumen Lectern"), "the lectern window closed meanwhile")
visit(s1)
ok(has(cmd(s1, "lecternStart", "seq:1").message, "begins"), "renewed attempt starts")
ok(has(cmd(s1, "lecternStart", "recall:1").message, "Finish your"), "one trial at a time")
ok(has(cmd(s1, "lecternEnd").message, "keep what you won"), "stop ends the trial")
eq(cmd(s1, "state").qol.lectern.left.seq, A.Games.seq.attempts - 1, "stopping keeps the attempt spent")

-- C7. Wardrobe.
local TA = Q.testArmour
local w1 = join(8201, function(pr)
	pr.items = {[TA.helm] = 1, [TA.chest] = 1, [TA.boots] = 1, [TA.gated] = 1, [TA.accs[1]] = 1, [TA.accs[2]] = 1, [TA.accs[3]] = 1, Blade = 1}
	pr.equipment = {weapon = "Blade", helmet = TA.helm, chest = TA.chest}
	pr.accessoryBag = {TA.accs[1], TA.accs[2]}
	pr.started = true
end)
local ws = cmd(w1, "state").qol.wardrobe
ok(ws.slots == 3 and ws.max == 9 and ws.sets[1] == false, "three empty loadouts at Combat 1")
ok(has(cmd(w1, "wardrobeSave", "4").message, "opens at Combat 15"), "slot 4 locked")
ok(has(cmd(w1, "wardrobeSave", "0").message, "Choose a wardrobe slot"), "slot 0 refused")
ok(has(cmd(w1, "wardrobeSave", "1.0").message, "Choose a wardrobe slot"), "non-canonical slot refused")
ok(has(cmd(w1, "wardrobeWear", "2").message, "empty"), "empty slot refused")
local sv = cmd(w1, "wardrobeSave", "1")
ok(has(sv.message, "Loadout 1 saved") and sv.qol.wardrobe.sets[1].helmet == TA.helm and #sv.qol.wardrobe.sets[1].acc == 2 and sv.qol.wardrobe.sets[1].weapon == nil, "loadout 1 saved (no weapon)")
-- Loadout 2: boots only, one other accessory.
cmd(w1, "unequip", "helmet"); cmd(w1, "unequip", "chest"); cmd(w1, "equip", TA.boots)
cmd(w1, "accessory", TA.accs[1]); cmd(w1, "accessory", TA.accs[2]); cmd(w1, "accessory", TA.accs[3])
local sv2 = cmd(w1, "wardrobeSave", "2")
ok(sv2.qol.wardrobe.sets[2].boots == TA.boots and sv2.qol.wardrobe.sets[2].helmet == nil and #sv2.qol.wardrobe.sets[2].acc == 1, "loadout 2 saved")
advance(W.COOLDOWN + 1)
local wear1 = cmd(w1, "wardrobeWear", "1")
ok(has(wear1.message, "Loadout 1 on"), "wear loadout 1")
local eqp = wear1.depth.equipment
ok(eqp.helmet == TA.helm and eqp.chest == TA.chest and eqp.boots == nil and eqp.weapon == "Blade", "armour swapped, empty slots cleared, weapon kept")
local bag = wear1.depth.accessoryBag
ok(#bag == 2 and table.find(bag, TA.accs[1]) and table.find(bag, TA.accs[2]) and not table.find(bag, TA.accs[3]), "accessory bag swapped")
eq(wear1.qol.wardrobe.worn, 1, "worn slot")
ok(has(cmd(w1, "wardrobeWear", "2").message, "settling"), "swap cooldown")
advance(W.COOLDOWN)
-- A hit holds the wardrobe.
ok(bridge.OnInvoke("damage", w1, {amount = 50}) > 0, "a hit lands")
ok(has(cmd(w1, "wardrobeWear", "2").message, "mid-fight"), "no swap right after a hit")
advance(W.HURT_GRACE)
local wear2 = cmd(w1, "wardrobeWear", "2")
ok(has(wear2.message, "Loadout 2 on") and wear2.depth.equipment.boots == TA.boots and wear2.depth.equipment.helmet == nil, "swap after the fight")
-- A sold piece refuses the whole set (nothing changes).
w1 = join(8201, function(pr) pr.items[TA.chest] = nil end)
advance(W.COOLDOWN + 1)
local bad = cmd(w1, "wardrobeWear", "1")
ok(has(bad.message, "no longer own"), "missing piece refused")
ok(bad.depth.equipment.boots == TA.boots and bad.depth.equipment.helmet == nil and #bad.depth.accessoryBag == 1, "a refused swap changes nothing")
-- Requirements and accessory room.
w1 = join(8201, function(pr)
	pr.items[TA.chest] = 1
	pr.wardrobe.sets["3"] = {helmet = TA.gated, acc = {}}
	pr.wardrobe.sets["2"] = {acc = {TA.accs[1], TA.accs[2], TA.accs[3], TA.accs[4]}}
	pr.items[TA.accs[4]] = 1
end)
ok(has(cmd(w1, "wardrobeWear", "3").message, "requires"), "requirements gate a loadout")
ok(has(cmd(w1, "wardrobeWear", "2").message, "accessory slots"), "accessory room gates a loadout")
ok(has(cmd(w1, "wardrobeClear", "3").message, "cleared") and cmd(w1, "state").qol.wardrobe.sets[3] == false, "clear a slot")
-- Combat 45: nine slots; Ironman uses the wardrobe too.
w1 = join(8201, function(pr) pr.xp.Combat = X[45]; pr.ironman = true end)
eq(cmd(w1, "state").qol.wardrobe.slots, 9, "nine loadouts at Combat 45")
ok(has(cmd(w1, "wardrobeSave", "9").message, "Loadout 9 saved"), "Ironman saves a loadout")

-- C8. Vault Charters.
local b1 = join(8301, function(pr) pr.bank = 80000; pr.coins = 30000; pr.started = true end)
local vs = cmd(b1, "state")
eq(vs.qol.vault.tier, 1, "Strongbox charter by default")
eq(vs.bank, 80000, "no interest on the first day seen")
eq(vs.qol.vault.next, 80, "tomorrow's interest preview")
utc = (Q.dayOf(utc) + 1) * DAY + 10
local paid = cmd(b1, "state")
eq(paid.bank, 80080, "one day of interest")
ok(has(paid.message, "Vault interest: +80"), "interest note")
eq(cmd(b1, "state").bank, 80080, "never twice a day")
b1 = join(8301)
eq(cmd(b1, "state").bank, 80080, "a rejoin the same day pays nothing")
ok(has(cmd(b1, "vaultUpgrade").message, "collection tier"), "charters need collections")
b1 = join(8301, function(pr) pr.collection.Ore = 300; pr.collection.Timber = 300; pr.bank = 900000 end)
local up = cmd(b1, "vaultUpgrade")
ok(has(up.message, "Coffer Charter"), "Coffer charter sealed")
eq(up.coins, 30000 - V.Tiers[2].cost, "paid from the purse")
eq(up.qol.vault.tier, 2, "tier 2")
utc = (Q.dayOf(utc) + 5) * DAY + 10
eq(cmd(b1, "state").bank, 900000 + V.maxDaily(V.Tiers[2]), "five days away pay one capped day")
ok(has(cmd(b1, "vaultUpgrade").message, "collection tier"), "next charter gated")

-- C9. Tethers.
local k1 = join(8401, function(pr)
	pr.xp.Enchanting = X[5]
	pr.pets = {{id = "Tidewing", level = 40, xp = 0}, {id = "Burrowmole", level = 40, xp = 0}}
	pr.activePet = 1
	pr.started = true
end)
ok(has(cmd(k1, "petTether", "2:Burrowmole").message, "Taming 10"), "tethers need Taming 10")
k1 = join(8401, function(pr) pr.xp.Taming = X[10] end)
ok(has(cmd(k1, "petTether", "2:Tidewing").message, "Choose one of your pets"), "species must match the index")
ok(has(cmd(k1, "petTether", "2:Burrowmole").message, "tethered"), "tether a pet")
ok(has(cmd(k1, "petTether", "1:Tidewing").message, "in use"), "tether limit at Taming 10")
local ts = cmd(k1, "state").qol.tether
ok(ts.slots == 1 and #ts.pets == 1 and ts.pets[1].index == 2 and ts.pets[1].sharing and ts.pets[1].activeXp == K.activeXpFor(ts.pets[1].need), "tether preview")
local before1 = saved(8401).pets
visit(k1)
cmd(k1, "lecternStart", "seq:1")
local sk = saved(8401).lectern.s
cmd(k1, "lecternAnswer", tostring(sk.seq[1]))
local after1 = saved(8401).pets
local activeGain = (after1[1].xp or 0) - (before1[1].xp or 0)
local kinGain = (after1[2].xp or 0) - (before1[2].xp or 0)
ok(activeGain > 0 and after1[1].level == 40, "the summoned pet earned XP")
ok(math.abs(kinGain - activeGain * K.SHARE) < 1e-6, "the tethered pet earned 10% (" .. kinGain .. " of " .. activeGain .. ")")
ok(has(cmd(k1, "petTether", "2:Burrowmole").message, "untethered"), "untether")

-- C10. Migration: malformed records are made safe and nothing is paid.
local m1 = join(8501, function(pr)
	pr.lectern = {day = Q.dayOf(utc + 2), used = {seq = 99, recall = -4, zz = 3}, bonus = 1e9, best = {seq = 0 / 0, pairs = 3}, runs = -2,
		s = {g = "seq", t = 9, seq = {1}, r = 1, ends = 0}}
	pr.wardrobe = {sets = {["1"] = {helmet = "Ore", acc = {"Ore"}}, ["2"] = {acc = {TA.accs[1], TA.accs[1]}}, ["12"] = {acc = {TA.accs[1]}}, x = 5}, worn = 44}
	pr.vault = {tier = 99, day = -1, paid = "lots"}
	pr.bank = 1000
	pr.pets = {{id = "Tidewing", level = 3, xp = 0, kin = "yes"}}
end)
local ms = saved(8501)
eq(ms.lectern.used.seq, A.Games.seq.attempts, "used clamped")
ok(ms.lectern.used.recall == nil and ms.lectern.used.zz == nil, "bad counts dropped")
ok(ms.lectern.bonus <= A.BONUS_CAP and ms.lectern.best.seq == nil and ms.lectern.best.pairs == 3 and ms.lectern.runs == 0, "lectern record sanitised")
eq(ms.lectern.s, nil, "a broken session is dropped")
ok(ms.wardrobe.sets["1"] == nil and #ms.wardrobe.sets["2"].acc == 1 and ms.wardrobe.sets["12"] == nil and ms.wardrobe.sets.x == nil and ms.wardrobe.worn == nil, "wardrobe sanitised")
ok(ms.vault.tier == 1 and ms.vault.paid == 0, "vault sanitised")
eq(ms.pets[1].kin, nil, "a non-boolean tether flag is dropped")
eq(cmd(m1, "state").bank, 1000, "migration pays no interest")
-- Bounded records: a full wardrobe and lectern stay small.
do
	local pr = saved(8201)
	local json = require("@lune/serde").encode("json", {pr.wardrobe, saved(8101).lectern})
	ok(#json < 8000, "QoL records stay small (" .. #json .. " bytes)")
end
print("PASS: " .. (checks - partC) .. " QoL server assertions.")
print("PASS: " .. checks .. " QoL assertions in total.")
print("SUITE-END verify-qol.luau")
