-- The Sundered Sky (§53): the eight-chapter main story.
-- Part A: the pure rules (Data.Story): chapters span every region with real
-- requirements (Runebinding / Skysailing included), step kinds, the cast and
-- 20+ dialogue nodes (distinct voices), rewards (untradeable, value 1, Quest
-- Points), lamps, puzzles (rune lock, constellation rings, light-beam mirrors:
-- solvable and server-checked), custom telegraph geometry, cutscene runner
-- (skip / death / teleport / damage / deadline always end it), migration.
-- Part B: combat.server.lua's Story section through the combat harness:
-- registration and caps, the lantern shroud, cross / beam / half hits, kill
-- credit, timeouts.
-- Part C: server.server.lua through the verify-gameplay harness: a full
-- playthrough of all eight chapters with requirement gating, step order that
-- cannot be skipped or spoofed, puzzles validated move by move, the beacon and
-- ship steps through the real Beaconry / Skysailing verbs, boss instances
-- (leave, death, disconnect, rejoin, a win settled at disconnect), rewards
-- granted once, lamps, persistence and migration, the helper pin, the
-- Loomheart fast travel.
-- Part D: story.server.lua headless (set pieces, arenas), the client's
-- restore paths and the registration in both build scripts.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local checks = 0
local function ok(cond, case)
	if not cond then error("FAILED: " .. case, 2) end
	checks += 1
end
local function eq(actual, expected, case)
	if actual ~= expected then error("FAILED: " .. case .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")", 2) end
	checks += 1
end
local function has(text, part) return type(text) == "string" and string.find(text, part, 1, true) ~= nil end
local function load(path, env)
	return luau.load((fs.readFile(path):gsub("^\239\187\191", "")), {debugName = path, environment = env or {}, injectGlobals = true})()
end
local Data = load("shared/GameData.lua")
local P = load("shared/Progression.lua", {script = nil})
P.useData(Data)
local ST = Data.Story
local T = Data.Townsfolk
local X = Data.XP_TABLE

------------------------------------------------------------------------------
-- A. Rules
------------------------------------------------------------------------------
local partA = checks
ok(type(ST) == "table" and ST.TITLE == "The Sundered Sky", "Data.Story exists")
eq(#ST.Chapters, 8, "eight chapters")
local KINDS = {talk = true, inspect = true, collect = true, kills = true, craft = true, beacon = true, sail = true, puzzle = true, boss = true}
do
	local regions, skillsUsed, kinds, bosses, puzzles = {}, {}, {}, {}, {}
	for i, ch in ipairs(ST.Chapters) do
		eq(ch.index, i, ch.id .. " index")
		ok(#ch.requires >= 1, ch.id .. " has requirements")
		for _, r in ipairs(ch.requires) do
			ok(Data.describeCheck(r) ~= "Unknown task", ch.id .. " requirement is a real check")
			if r.kind == "level" then skillsUsed[r.skill] = true; ok(Data.Skills[r.skill] ~= nil, ch.id .. " skill " .. r.skill) end
		end
		for _, r in ipairs(ch.regions) do regions[r] = true end
		ok(#ch.steps >= 4, ch.id .. " is multi-step (" .. #ch.steps .. ")")
		eq(ch.steps[1].kind, "talk", ch.id .. " opens with a talk to its giver")
		eq(ch.steps[1].npc, ch.giver, ch.id .. " giver")
		eq(ch.steps[#ch.steps].kind, "talk", ch.id .. " closes with a talk")
		for j, s in ipairs(ch.steps) do
			ok(KINDS[s.kind], ch.id .. " step " .. j .. " kind " .. tostring(s.kind))
			kinds[s.kind] = true
			ok(type(s.text) == "string" and #s.text > 8, ch.id .. " step " .. j .. " text")
			if s.kind == "talk" then ok(ST.CastByRole[s.npc] and #s.lines > 30 and #s.ask <= 80 and #s.reply <= 80, ch.id .. " talk " .. j) end
			if s.kind == "collect" or s.kind == "craft" then ok(Data.Items[s.item] and s.count > 0, ch.id .. " item " .. s.item) end
			if s.kind == "kills" then ok(Data.Monsters[s.monster] and s.count > 0, ch.id .. " monster " .. s.monster) end
			if s.kind == "beacon" then ok(Data.Beaconry.Beacons[s.beacon] ~= nil, ch.id .. " beacon") end
			if s.kind == "sail" then ok(Data.Skysailing.PortById[s.port] ~= nil, ch.id .. " port") end
			if s.kind == "inspect" then for _, piece in ipairs(s.pieces) do ok(ST.PieceById[piece] ~= nil, ch.id .. " piece " .. piece) end end
			if s.kind == "puzzle" then puzzles[s.puzzle] = true; ok(ST.Puzzles[s.puzzle] ~= nil, ch.id .. " puzzle") end
			if s.kind == "boss" then bosses[s.boss] = true; ok(ST.Bosses[s.boss] ~= nil, ch.id .. " boss") end
			if s.cut then ok(ST.Cutscenes[s.cut] ~= nil, ch.id .. " cutscene " .. s.cut) end
		end
		ok(ch.rewards.points >= 1, ch.id .. " pays Quest Points")
		ok(#(ch.rewards.lamps or {}) >= 1, ch.id .. " pays an XP lamp")
	end
	for _, r in ipairs(Data.Regions) do ok(regions[r.id], "the story visits " .. r.id) end
	ok(regions.ShatteredCrown, "the story visits the Shattered Crown")
	ok(skillsUsed.Runebinding and skillsUsed.Skysailing, "Runebinding and Skysailing gate chapters")
	for k in pairs(KINDS) do ok(kinds[k], "a step of kind " .. k) end
	local nb = 0
	for _ in pairs(bosses) do nb += 1 end
	ok(nb >= 3, "at least three instanced bosses")
	ok(puzzles.runelock and puzzles.stars and puzzles.mirrors, "rune lock, constellation and mirror puzzles")
	eq(ST.maxPoints(), 18, "18 story Quest Points")
	eq(ST.points({ch = 1}), 0, "no points before chapter 1")
	eq(ST.points({ch = 9}), 18, "all points at the end")
	eq(ST.points({ch = 4}), 5, "points of finished chapters only")
	-- Later chapters gate on Quest Points that earlier content pays.
	local gated = false
	for _, ch in ipairs(ST.Chapters) do for _, r in ipairs(ch.requires) do if r.kind == "questPoints" then gated = true end end end
	ok(gated, "Quest Point gates")
	eq(ST.Chapters[8].rewards.unlock.warp, "Loomheart", "the finale unlocks the Loomheart node")
end
-- The cast, voices and dialogue graph.
do
	local nodes, names, colors = 0, {}, {}
	eq(#ST.Cast, 9, "nine cast members")
	for _, c in ipairs(ST.Cast) do
		local npc = T.NPCs[c.role]
		ok(npc and npc.anchorOnly and table.find(T.RegionFolkOrder, c.role), c.role .. " is regional folk on an anchor")
		ok(Data.RegionArt.FolkByRole[c.role] ~= nil, c.role .. " in RA.Folk (world anchors)")
		ok(not names[c.name] and not colors[c.color], c.role .. " distinct name and colour")
		names[c.name], colors[c.color] = true, true
		ok(type(c.voice) == "string", c.role .. " voice")
		for id, node in pairs(npc.nodes) do
			nodes += 1
			ok(#node.text > 20, c.role .. "." .. id .. " has lines")
			for _, o in ipairs(node.options) do
				ok(#o.label <= Data.RegionArt.LABEL_MAX, c.role .. " label length")
				if o.verb then eq(o.verb, "storyTalk", "story options only send storyTalk"); eq(o.item, c.role, "talk item is the speaker") end
				if o.when then ok(T.Conditions[o.when] ~= nil, "condition " .. o.when) end
			end
		end
	end
	ok(nodes >= 20, "20+ dialogue nodes (" .. nodes .. ")")
	local voices = {}
	for _, c in ipairs(ST.Cast) do voices[c.voice] = true end
	local nv = 0
	for _ in pairs(voices) do nv += 1 end
	eq(nv, 9, "nine distinct voices")
	-- Conditions show a talk node only while its step is current.
	local snap = {story = {cur = {ch = 1, step = 1, kind = "talk", npc = "StoryArchivist", ready = false}}}
	local hello = T.NPCs.StoryArchivist.nodes.hello
	local function visible(s) local out = {} for _, o in ipairs(T.visibleOptions(hello, s, {})) do out[o.label] = true end return out end
	ok(not visible(snap)["Story: the fraying sky"], "chapter 1 offer hidden while requirements are unmet")
	snap.story.cur.ready = true
	ok(visible(snap)["Story: the fraying sky"], "chapter 1 offer shown when ready")
	snap.story.cur.step = 2
	ok(not visible(snap)["Story: the fraying sky"], "a passed step's talk is hidden")
	ok(has(T.Tips.story({story = {cur = {ch = 2, step = 1, ready = false, reqs = {{text = "Mining level 20", met = false}}}}}), "Mining level 20"), "the story tip lists missing requirements")
	ok(has(T.Tips.story({story = {done = true}}), "complete"), "tip after the end")
	ok(T.Verbs.storyTalk.item.StoryArchivist and not T.Verbs.storyTalk.item.Banker, "storyTalk item whitelist")
end
-- Rewards: unique, untradeable, worth nothing to a merchant.
do
	local n = 0
	for _, ch in ipairs(ST.Chapters) do
		for id, k in pairs(ch.rewards.items or {}) do
			local def = Data.Items[id]
			n += 1
			ok(def and def.untradeable == true and def.value == 1 and def.story == true, id .. " is untradeable, value 1")
			ok(Data.Economy.untradeable(id) and not Data.Economy.isCommodity(id) and Data.Economy.auctionCategory(id) == nil, id .. " never trades")
			eq(k, 1, id .. " one copy")
			for stat in pairs(def.stats) do ok(Data.Stats[stat] ~= nil, id .. " stat " .. stat) end
		end
	end
	ok(n >= 6, "six unique rewards")
	-- Lamps scale with the chosen skill's level.
	ok(ST.lampXp(20, 1) < ST.lampXp(20, 50) and ST.lampXp(20, 50) < ST.lampXp(20, 99), "lamp XP scales with level")
	eq(ST.lampXp(20, 150), ST.lampXp(20, 99), "lamp level clamps at 99")
	ok(ST.LAMP_EXCLUDE.Dungeoneering and ST.LAMP_EXCLUDE.Carpentry, "lamps never train gated skills")
	local total = 0
	for _, ch in ipairs(ST.Chapters) do for _, l in ipairs(ch.rewards.lamps) do total += ST.lampXp(l.rate, 99) end end
	ok(total < X[99] * 0.05, "every lamp at 99 is under 5% of a 99 (" .. total .. ")")
end
-- Puzzles.
do
	-- Rune lock: four distinct runes per journal, deterministic, seeds differ.
	local seen = {}
	for uid = 1, 40 do
		local sol = ST.runeSolution(ST.seedOf(uid))
		eq(#sol, ST.DIALS, "four dials")
		local set = {}
		for _, r in ipairs(sol) do ok(table.find(ST.RUNES, r) and not set[r], "distinct real runes"); set[r] = true end
		seen[table.concat(sol, ",")] = true
	end
	local variety = 0
	for _ in pairs(seen) do variety += 1 end
	ok(variety >= 10, "answers vary between journals (" .. variety .. ")")
	eq(table.concat(ST.runeSolution(ST.seedOf(7)), ","), table.concat(ST.runeSolution(ST.seedOf(7)), ","), "the same journal, the same answer")
	local pz = ST.puzzleStart("runelock", ST.seedOf(7))
	ok(not ST.puzzleSolved(pz, ST.seedOf(7)), "a blank lock is shut")
	pz.s = ST.runeSolution(ST.seedOf(7))
	ok(ST.puzzleSolved(pz, ST.seedOf(7)) and not ST.puzzleSolved(pz, ST.seedOf(8)) or table.concat(ST.runeSolution(ST.seedOf(8))) == table.concat(pz.s), "only the journal's own answer opens it")
	-- Constellation rings: always a real scramble of real moves; solvable.
	local function solveStars(s)
		for code = 0, ST.STOPS ^ ST.RINGS - 1 do
			local c, x = {}, code
			for i = 1, ST.RINGS do c[i] = x % ST.STOPS; x //= ST.STOPS end
			local good = true
			for i = 1, ST.RINGS do
				local prev = if i == 1 then ST.RINGS else i - 1
				if (s[i] + c[i] + c[prev]) % ST.STOPS ~= 0 then good = false break end
			end
			if good then return c end
		end
		return nil
	end
	for uid = 1, 12 do
		local s = ST.starStart(ST.seedOf(uid))
		ok(not ST.starSolved(s), "the astrolabe starts out of true (" .. uid .. ")")
		local c = solveStars(s)
		ok(c ~= nil, "the rings are solvable (" .. uid .. ")")
		for i = 1, ST.RINGS do for _ = 1, c[i] do ST.starTurn(s, i) end end
		ok(ST.starSolved(s), "the solution aligns every ring")
	end
	ok(not ST.starTurn({0, 0, 0, 0, 0}, 6) and not ST.starTurn({0, 0, 0, 0, 0}, 0), "ring index bounds")
	-- Mirrors: exactly one of the 64 settings lights the lens; every start is dark.
	local n = #ST.Mirror.mirrors
	local sols = 0
	for m = 0, 2 ^ n - 1 do
		local s = {}
		for i = 1, n do s[i] = (m // 2 ^ (i - 1)) % 2 end
		local lit, path, why = ST.traceBeam(s)
		if lit then sols += 1; ok(#path >= 12, "the beam crosses the field (" .. #path .. " cells)") else ok(why ~= nil, "a dark beam says why") end
	end
	eq(sols, 1, "one mirror setting lights the lens")
	for uid = 1, 12 do ok(not ST.traceBeam(ST.mirrorStart(ST.seedOf(uid))), "the mirrors start dark (" .. uid .. ")") end
	-- Move whitelist.
	ok(ST.parseMove("stars:turn:3") and ST.parseMove("mirrors:turn:6") and ST.parseMove("runelock:set:2:EmberRune") and ST.parseMove("runelock:try") and ST.parseMove("stars:reset"), "real moves parse")
	for _, bad in ipairs({"stars:turn:9", "stars:turn:0", "mirrors:turn:7", "runelock:set:5:GaleRune", "runelock:set:1:GoldOre", "runelock:solve", "stars:win", "nope:turn:1", "stars:turn:1.5", string.rep("a", 60), 42}) do
		eq(ST.parseMove(bad), nil, "refused move " .. tostring(bad))
	end
end
-- Bosses and their unique geometry.
do
	for _, id in ipairs(ST.BossOrder) do
		local def = ST.Bosses[id]
		ok(def.lair and def.story and def.hp > 0 and def.weakness and #def.phases >= 2, id .. " is a lair-shaped definition")
		ok(Data.Monsters[id] == def and Data.Lairs.boss(id) == nil, id .. " reachable by id but never a lair boss")
		for _, a in pairs(def.attacks) do
			if a.windup then ok(a.windup >= 0.6, id .. " " .. a.id .. " readable windup") end
			if a.add then ok(Data.Lairs.Adds[a.add] ~= nil and Data.Monsters[a.add] ~= nil, id .. " add " .. a.add .. " resolves") end
		end
		for _, phase in ipairs(def.phases) do for _, atk in ipairs(phase.rotation) do ok(def.attacks[atk] ~= nil, id .. " rotation " .. atk) end end
	end
	ok(ST.Bosses.Gloamwick.lanterns and #ST.lanternSpots(ST.Bosses.Gloamwick) == 4, "Gloamwick's four lanterns")
	local seenCustom = {}
	for _, id in ipairs(ST.BossOrder) do for _, a in pairs(ST.Bosses[id].attacks) do if ST.CUSTOM_TELEGRAPH[a.kind] then seenCustom[a.kind] = true end end end
	ok(seenCustom.cross and seenCustom.beam and seenCustom.half, "cross, beam and half telegraphs are used")
	-- Lanterns move every relight, deterministic.
	local prev
	for n = 1, 30 do
		local lit = ST.litLantern(5, n, 4, prev)
		ok(lit >= 1 and lit <= 4 and lit ~= prev, "the light always moves")
		prev = lit
	end
	local def = ST.Bosses.Gloamwick
	local spot = ST.lanternSpots(def)[2]
	ok(ST.inLight(def, 2, spot.x + 2, spot.z) and not ST.inLight(def, 2, 0, 0) and not ST.inLight(def, 3, spot.x, spot.z), "inLight")
	ok(ST.inLight(ST.Bosses.Vaelith, nil, 99, 99), "no lanterns: always lit")
	local tg = {cx = 0, cz = 0, ux = 1, uz = 0}
	local cross = ST.Bosses.Vaelith.attacks.cross
	ok(ST.struck(cross, tg, 20, 0) and ST.struck(cross, tg, 0, -20) and not ST.struck(cross, tg, 10, 10), "cross: on the arms, safe between")
	ok(not ST.struck(cross, tg, 30, 0), "cross arms end")
	local beam = ST.Bosses.Caedmon.attacks.beam
	ok(ST.struck(beam, tg, 30, 1) and not ST.struck(beam, tg, -5, 0) and not ST.struck(beam, tg, 30, 5), "beam: ahead and narrow")
	local half = ST.Bosses.Caedmon.attacks.sunder
	ok(ST.struck(half, tg, 5, 30) and not ST.struck(half, tg, -5, 30), "half: one side of the line")
end
-- Cutscenes: capped, and the runner always ends.
do
	eq(#ST.CutsceneOrder, 11, "eleven cutscenes")
	for _, id in ipairs(ST.CutsceneOrder) do
		local c = ST.Cutscenes[id]
		ok(c.total <= ST.CUTSCENE_MAX and #c.shots >= 1, id .. " is short")
		for _, s in ipairs(c.shots) do
			ok(ST.Voices[s.speaker] ~= nil, id .. " speaker " .. tostring(s.speaker))
			ok(type(s.line) == "string" and #s.line > 10 and s.dur > 1, id .. " shot")
		end
		-- Played to the end.
		local run = ST.cutStart(id, 100)
		local ended, t = false, 100
		while not ended and t < 100 + ST.CUTSCENE_MAX + 10 do t += 0.1; _, ended = ST.cutStep(run, t, {}) end
		ok(ended and t <= 100 + c.total + 0.2 and run.reason == "done", id .. " ends on its own (" .. tostring(run.reason) .. ")")
		for _, ev in ipairs({{skip = true}, {dead = true}, {teleported = true}, {hurt = true}, {missing = true}}) do
			local r = ST.cutStart(id, 0)
			local _, e = ST.cutStep(r, 0.5, ev)
			ok(e and r.reason ~= nil, id .. " ends at once on " .. tostring(next(ev)))
		end
		-- Even a frozen shot clock never holds past the deadline.
		local r = ST.cutStart(id, 0)
		r.shotEnds = math.huge
		local _, e = ST.cutStep(r, c.total + ST.CUTSCENE_GRACE + 0.01, {})
		ok(e and r.reason == "deadline", id .. " deadline watchdog")
	end
	eq(ST.cutStart("nope", 0), nil, "unknown cutscene")
	local _, e = ST.cutStep(nil, 0, {})
	ok(e, "a missing run counts as ended")
	-- Replays unlock with progress.
	eq(#ST.unlockedCutscenes({ch = 1, step = 1}), 0, "nothing to replay at the start")
	eq(#ST.unlockedCutscenes({ch = 9, step = 1}), 11, "everything after the end")
	ok(table.find(ST.unlockedCutscenes({ch = 1, step = 2}), "c1_intro"), "the intro after accepting")
end
-- Migration.
do
	local m = ST.migrate(nil)
	eq(m.ch, 1, "fresh: chapter 1"); eq(m.step, 1, "fresh: step 1"); eq(#m.lamps, 0, "no lamps")
	m = ST.migrate({ch = 99, step = -4, lamps = {{rate = 20}, {rate = 0}, {rate = 500}, "x"}, cut = {id = "nope"}, marks = {SkyTear = true}})
	eq(m.ch, 9, "chapter clamps to done"); eq(#m.lamps, 1, "only sane lamps kept"); eq(m.cut, nil, "unknown cutscene dropped")
	m = ST.migrate({ch = 1, step = 4, marks = {SkyTear = true, GlyphStone1 = true, Junk = 1}})
	ok(m.marks.SkyTear and not m.marks.GlyphStone1, "marks only for the current inspect step")
	m = ST.migrate({ch = 2, step = 4, puzzle = {id = "runelock", s = {"GaleRune", "Gold", 5, "TideRune"}}})
	eq(m.puzzle.s[2], "", "unknown runes cleared"); eq(m.puzzle.s[1], "GaleRune", "real runes kept")
	m = ST.migrate({ch = 2, step = 4, puzzle = {id = "stars", s = {1, 2, 3, 4, 5}}})
	eq(m.puzzle, nil, "a puzzle that is not the step's is dropped")
	m = ST.migrate({ch = 5, step = 3, puzzle = {id = "stars", s = {9, -1, 3.5, 0, 7}}})
	ok(m.puzzle.s[1] == 1 and m.puzzle.s[2] == 7 and m.puzzle.s[3] == 3, "ring stops wrapped")
	local many = {}
	for i = 1, 40 do many[i] = {rate = 10} end
	eq(#ST.migrate({lamps = many}).lamps, ST.MAX_LAMPS, "lamps capped")
	eq(ST.migrate({ch = 3, step = 99}).step, #ST.Chapters[3].steps, "step clamps to the chapter")
end
-- Helper guide (§33).
do
	ok(Data.Systems.Helper.validPin("story") and Data.Systems.Helper.validPin("quest:SurveyorsOath"), "story pin is valid (and quests still are)")
	local g = ST.guide({ch = 2, step = 1, reqs = {{text = "Mining level 20", met = false}, {text = "Runebinding level 10", met = true}}})
	eq(g.status, "locked", "a locked chapter's guide")
	eq(g.steps[g.current].text, "Mining level 20", "the guide points at the missing requirement")
	g = ST.guide({ch = 2, step = 3, have = 1, need = 4, marks = {GlyphStone1 = true}})
	eq(g.status, "active", "active guide")
	local s = g.steps[g.current]
	ok(has(s.text, "glyph stones") and s.have == 1 and s.need == 4, "guide step counts")
	ok(s.specs and #s.specs == 3 and not table.find(s.specs, "anchor:Story_GlyphStone1"), "waypoints skip studied stones")
	eq(ST.specsFor(ST.Chapters[3].steps[5])[1], "anchor:Story_GloamGate", "boss steps guide to their gate")
	eq(ST.specsFor(ST.Chapters[1].steps[1])[1], "npc:StoryArchivist", "talks guide to the NPC")
	eq(ST.specsFor(ST.Chapters[4].steps[2])[1], "anchor:Dock_Tidewater", "the sail step guides to the dock")
	for _, spec in ipairs({"anchor:Story_GloamGate", "npc:StoryArchivist", "anchor:Dock_Tidewater"}) do ok(T.parseTarget(spec) ~= nil, spec .. " is a Wayfinder target") end
	eq(Data.Features.announceText({kind = "story", title = "1. A Tear in the Sky", points = 1}).head, "CHAPTER COMPLETE", "story announcement")
end
-- QC regressions (rules).
do
	-- [M2] the arena's corners sit inside the inside range, and both sides use the same range.
	ok(ST.ARENA_HALF * math.sqrt(2) <= ST.ARENA_RANGE, "[M2] arena corners inside ST.ARENA_RANGE")
	eq(ST.ARENA_RANGE, Data.Lairs.ARENA_RANGE, "[M2] the story range is combat's inside range")
	-- [M1 / M3] one shared travel guard.
	local function fake(attrs, seat)
		local humanoid = {SeatPart = seat}
		return {GetAttribute = function(_, k) return attrs[k] end, Character = {FindFirstChildOfClass = function() return humanoid end}}
	end
	eq(ST.travelBlock(fake({})), nil, "[M3] free to travel")
	ok(has(ST.travelBlock(fake({StoryFight = "Gloamwick"})), "encounter"), "[M1] an encounter blocks travel")
	ok(has(ST.travelBlock(fake({SailVessel = "4:helm"})), "ship"), "[M3] aboard a ship blocks travel")
	ok(has(ST.travelBlock(fake({}, {})), "Stand up"), "[M3] seated blocks travel")
	eq(ST.travelBlock(fake({LairBoss = "Bramblemaw"})), nil, "the gate leaves lairs to their own rules")
	ok(has(ST.travelBlock(fake({LairBoss = "Bramblemaw"}), true), "Finish"), "[M1] busy = true refuses other activities")
	ok(has(ST.travelBlock(fake({DungeonInRun = true}), true), "Finish"), "[M1] dungeon runs too")
	-- [L6] a named cutscene waits for calm.
	local calm = {}
	ok(ST.cutCalm(calm, 10, 100, true), "[L6] calm at once without damage")
	ok(not ST.cutCalm(calm, 11, 80, true), "[L6] damage holds it")
	ok(not ST.cutCalm(calm, 11 + ST.CUT_CALM - 0.5, 80, true), "[L6] still held inside the calm window")
	ok(ST.cutCalm(calm, 11 + ST.CUT_CALM + 0.1, 80, true), "[L6] plays after the calm window")
	ok(not ST.cutCalm({}, 50, 0, false), "[L6] never while dead")
	-- [L13] versioned step remaps.
	local version = ST.VERSION
	ST.VERSION = 2
	ST.REMAPS[1] = {Vault = {[3] = 4}}
	local m = ST.migrate({v = 1, ch = 2, step = 3, marks = {GlyphStone1 = true}, base = 9})
	eq(m.step, 4, "[L13] a remap moves an old step")
	ok(next(m.marks) == nil and m.base == 0, "[L13] a moved step starts clean")
	eq(ST.migrate({v = 1, ch = 2, step = 2}).step, 2, "[L13] unlisted steps keep their index")
	eq(ST.migrate({v = 2, ch = 2, step = 3}).step, 3, "[L13] current saves are not remapped")
	ST.VERSION = version
	ST.REMAPS[1] = nil
	eq(ST.migrate({v = 1, ch = 2, step = 3}).step, 3, "[L13] no remap at version 1")
end
print("Part A (rules): " .. (checks - partA) .. " checks")

------------------------------------------------------------------------------
-- B. Combat logic (Story section)
------------------------------------------------------------------------------
local partB = checks
local Combat
load("combat.server.lua", {Vector3 = Vector3, CFrame = CFrame, Color3 = roblox.Color3, __CombatTestHarness = function(exports) Combat = exports end})
local function world()
	local w = {clock = 100, rolls = {}, calls = {}, positions = {}, alive = {}, stats = {}, list = {}}
	function w.rng() if #w.rolls > 0 then return table.remove(w.rolls, 1) end return 0.5 end
	function w.player(id, pos)
		local p = {Name = "P" .. id, UserId = id}
		w.positions[p] = pos
		w.alive[p] = true
		w.stats[p] = {stats = {damage = 4000, strength = 300, critChance = 0, critDamage = 50, attackSpeed = 0}, combatLevel = 99, ironman = false,
			loadout = {style = "melee", levels = {}, supplies = {}}}
		table.insert(w.list, p)
		return p
	end
	function w.damageTo(p)
		local n = 0
		for _, c in ipairs(w.calls) do if c.op == "damage" and c.player == p then n += 1 end end
		return n
	end
	w.logic = Combat.createLogic({
		Data = Data, Progression = P,
		now = function() return w.clock end, time = function() return 5000 end, rng = w.rng,
		players = function() return w.list end,
		alive = function(p) return w.alive[p] == true end,
		position = function(p) return w.positions[p] end,
		heal = function() end,
		bridge = function(op, player, payload, done)
			table.insert(w.calls, {op = op, player = player, payload = payload})
			if op == "stats" then return w.stats[player] end
			if done then done(nil) end
			return nil
		end,
		lineOfSight = function() return true end,
	})
	return w
end
local function tickLogic(w, seconds, step)
	step = step or 0.25
	local t, events = 0, {}
	while t < seconds - 1e-9 do
		w.clock += step
		t += step
		w.logic.beginTick()
		for _, e in ipairs(w.logic.lrTick()) do table.insert(events, e) end
		for _, r in ipairs(w.logic.records()) do w.logic.think(r) end
		w.logic.endTick()
	end
	return events
end
local LR = Data.Lairs
do
	local w = world()
	local center = Vector3.new(0, 0, 0)
	local hero = w.player(901, center + Vector3.new(0, 0, -20))
	local stranger = w.player(902, center + Vector3.new(0, 0, -18))
	local r = w.logic.stRegister("story:901:1", "Gloamwick", {Name = "Gloamwick"}, center + Vector3.new(0, 3, 11), {members = {901}, seed = 4, center = center, ground = 0})
	ok(r and r.story and r.lair and r.maxHp == ST.Bosses.Gloamwick.hp, "a story encounter is a lair-shaped record")
	eq(w.logic.stRegister("story:901:1", "Gloamwick", {}, center, {members = {901}, center = center}), nil, "one record per fight")
	eq(w.logic.stRegister("story:x", "Bramblemaw", {}, center, {members = {901}, center = center}), nil, "only story bosses register")
	eq(w.logic.stRegister("story:y", "Vaelith", {}, center, {members = {}, center = center}), nil, "a member is required")
	-- The story cap, and lairs are never crowded out.
	for i = 2, ST.MAX_FIGHTS do ok(w.logic.stRegister("story:c" .. i, "Vaelith", {Name = "V"}, center + Vector3.new(i * 400, 3, 0), {members = {900 + i}, center = center + Vector3.new(i * 400, 0, 0)}), "story slot " .. i) end
	eq(w.logic.stRegister("story:over", "Vaelith", {Name = "V"}, center, {members = {1}, center = center}), nil, "story cap (" .. ST.MAX_FIGHTS .. ")")
	ok(w.logic.lrRegister("L:1", "Bramblemaw", {Name = "B"}, center + Vector3.new(9000, 3, 0), {members = {1}, center = center + Vector3.new(9000, 0, 0)}), "a lair fight still registers with every story slot full")
	w.logic.lrDespawn("L:1")
	for i = 2, ST.MAX_FIGHTS do w.logic.lrDespawn("story:c" .. i) end
	-- Members only; the shroud.
	tickLogic(w, 0.25)
	ok(r.lit ~= nil, "a lantern is lit at the rise")
	local spots = ST.lanternSpots(r.def)
	local dark = spots[r.lit % 4 + 1]
	w.positions[stranger] = r.position + Vector3.new(0, 0, 3)
	w.clock += 1
	local res, why = w.logic.attack(stranger, "attack", r.model)
	ok(res == nil and why == "lair", "outsiders cannot strike (" .. tostring(why) .. ")")
	w.positions[hero] = Vector3.new(dark.x, 0, dark.z)
	r.position = Vector3.new(dark.x, 3, dark.z + 3)
	w.clock += 1
	res, why = w.logic.attack(hero, "attack", r.model)
	ok(res == nil and why == "shrouded", "outside the light the boss is shrouded (" .. tostring(why) .. ")")
	local lit = spots[r.lit]
	w.positions[hero] = Vector3.new(lit.x, 0, lit.z)
	r.position = Vector3.new(lit.x, 3, lit.z + 3)
	w.clock += 1
	res = w.logic.attack(hero, "attack", r.model)
	ok(res and (res.damage or 0) > 0, "inside the light the blow lands")
	-- The light moves on its timer (event "lantern").
	local before = r.lit
	local events = tickLogic(w, r.def.lanterns.every + 0.5)
	local moved = false
	for _, e in ipairs(events) do if e.kind == "lantern" and e.record == r then moved = true end end
	ok(moved and r.lit ~= before, "the lantern moves")
	-- [M2] a member outside the arena cannot strike (the boss leashes back to the centre).
	w.positions[hero] = center + Vector3.new(ST.ARENA_RANGE + 6, 0, 0)
	r.position = center + Vector3.new(ST.ARENA_RANGE + 3, 3, 0)
	w.clock += 1
	res, why = w.logic.attack(hero, "attack", r.model)
	ok(res == nil and why == "outside", "[M2] hits from outside the arena are refused (" .. tostring(why) .. ")")
	-- Kill credit: the member alive with damage.
	w.logic.kill(r)
	local result = w.logic.lrResult("story:901:1")
	ok(result and result.result == "win" and result.credit[901].ok == true, "the member is credited")
	local status = w.logic.lrStatus("story:901:1")
	ok(status.alive == false and status.result == "win", "status after the kill")
end
do
	-- A member who never struck, or is down at the kill, is not credited.
	local w = world()
	local center = Vector3.new(0, 0, 0)
	local idle = w.player(911, center)
	local r = w.logic.stRegister("story:911:1", "Vaelith", {Name = "V"}, center + Vector3.new(0, 3, 11), {members = {911}, center = center, ground = 0})
	w.logic.kill(r)
	eq(w.logic.lrResult("story:911:1").credit[911].ok, false, "no damage, no credit")
	local w2 = world()
	local down = w2.player(912, center + Vector3.new(0, 0, -6))
	local r2 = w2.logic.stRegister("story:912:1", "Vaelith", {Name = "V"}, center + Vector3.new(0, 3, 4), {members = {912}, center = center, ground = 0})
	w2.clock += 1
	w2.positions[down] = r2.position + Vector3.new(0, 0, 3)
	ok(w2.logic.attack(down, "attack", r2.model), "a hit lands")
	w2.alive[down] = false
	w2.logic.kill(r2)
	eq(w2.logic.lrResult("story:912:1").credit[912].ok, false, "down at the kill, no credit")
	local _ = idle
end
do
	-- Custom telegraphs hit by their own geometry; dodging works.
	local w = world()
	local center = Vector3.new(0, 0, 0)
	local hero = w.player(921, center + Vector3.new(0, 0, -6))
	local r = w.logic.stRegister("story:921:1", "Caedmon", {Name = "C"}, center + Vector3.new(0, 3, 0), {members = {921}, seed = 9, center = center, ground = 0})
	r.position = center + Vector3.new(0, 3, 0)
	local seen = {}
	for _ = 1, 200 do
		local events = tickLogic(w, 0.5)
		for _, e in ipairs(events) do
			if e.kind == "telegraph" and e.record == r and ST.CUSTOM_TELEGRAPH[e.telegraph.kind] then
				local tg = e.telegraph
				ok(tg.ux and tg.uz and math.abs(tg.ux * tg.ux + tg.uz * tg.uz - 1) < 1e-6, tg.kind .. " has a unit direction")
				-- Stand where the geometry says: struck once, safe once.
				local safeSpot
				for _, cand in ipairs({{20, 20}, {-20, 20}, {20, -20}, {-20, -20}, {25, 0}, {-25, 0}, {0, 25}, {0, -25}}) do
					if not ST.struck(tg.attack, tg, cand[1], cand[2]) then safeSpot = cand break end
				end
				seen[tg.kind] = (seen[tg.kind] or 0) + 1
				local struckRun = seen[tg.kind] % 2 == 1
				if struckRun then
					local hit
					for _, cand in ipairs({{tg.cx + tg.ux * 6, tg.cz + tg.uz * 6}, {tg.cx + tg.ux * 3, tg.cz + tg.uz * 3}}) do
						if ST.struck(tg.attack, tg, cand[1], cand[2]) then hit = cand break end
					end
					w.positions[hero] = Vector3.new(hit[1], 0, hit[2])
				else
					w.positions[hero] = Vector3.new(safeSpot[1], 0, safeSpot[2])
				end
				local before = w.damageTo(hero)
				local strikes = tickLogic(w, tg.windup + 0.3)
				local hits = 0
				for _, s in ipairs(strikes) do if s.kind == "strike" and s.telegraph == tg then hits = #s.hits end end
				if struckRun then ok(hits == 1 and w.damageTo(hero) > before, tg.kind .. " strikes inside its shape")
				else eq(hits, 0, tg.kind .. " misses outside its shape") end
				w.positions[hero] = center + Vector3.new(0, 0, -6)
			end
		end
		if (seen.beam or 0) >= 2 and (seen.half or 0) >= 2 then break end
	end
	ok((seen.beam or 0) >= 2 and (seen.half or 0) >= 2, "Unravel and Sunder both fired (beam " .. tostring(seen.beam) .. ", half " .. tostring(seen.half) .. ")")
	-- Timeout.
	w.clock = r.expires + 1
	tickLogic(w, 0.25)
	eq(w.logic.lrResult("story:921:1").result, "timeout", "the fight times out")
end
do
	local w = world()
	local center = Vector3.new(0, 0, 0)
	local hero = w.player(931, center + Vector3.new(0, 0, -6))
	local r = w.logic.stRegister("story:931:1", "Vaelith", {Name = "V"}, center + Vector3.new(0, 3, 0), {members = {931}, seed = 2, center = center, ground = 0})
	local crossSeen = false
	for _ = 1, 80 do
		for _, e in ipairs(tickLogic(w, 0.5)) do if e.kind == "telegraph" and e.telegraph.kind == "cross" then crossSeen = true end end
		if crossSeen then break end
	end
	ok(crossSeen, "Vaelith raises Stormcross")
	local _ = hero
	local _r = r
end
print("Part B (combat): " .. (checks - partB) .. " checks")

------------------------------------------------------------------------------
-- C. Server
------------------------------------------------------------------------------
local partC = checks
local src = (fs.readFile("verify-gameplay.luau"):gsub("\r\n", "\n"))
local cut = src:find("local checks=0\nlocal function eq", 1, true)
assert(cut, "verify-gameplay harness marker")
local prefix = src:sub(1, cut - 1)
local n1, n2, n3, n4, n5
prefix, n1 = prefix:gsub("local workspace = {GetAttribute=function%(self,key%) return self%[key%] end}", "local workspace = __ws")
prefix, n2 = prefix:gsub("\tworkspace=workspace,\n", "\tworkspace=workspace,CFrame=__roblox.CFrame,Vector3=__roblox.Vector3,\n")
prefix, n3 = prefix:gsub("ServerStorage={},", "ServerStorage={FindFirstChild=function(_, n) return __storage[n] end},")
prefix, n4 = prefix:gsub("spawn=function%(f,%.%.%.%) assert%(coroutine%.resume%(coroutine%.create%(f%),%.%.%.%)%) end,",
	"spawn=function(f,...) local co=coroutine.create(f); local ok,y=coroutine.resume(co,...); assert(ok,y); table.insert(__loops,{co=co,y=y}) end,")
prefix, n5 = prefix:gsub("wait=function%(%) coroutine%.yield%(%) end,", "wait=function(t) return coroutine.yield(t) end,")
assert(n1 == 1 and n2 == 1 and n3 == 1 and n4 == 1 and n5 == 1, "harness hooks")
-- Fakes: travel gate, vessel host (Skysailing), story host, story combat (the real combat logic).
local gate = {Invoke = function() return true end}
local Vessel = {ships = {}}
local vesselFn = {Invoke = function(_, op, payload)
	local v = payload and Vessel.ships[payload.id]
	if op == "spawn" then
		Vessel.ships[payload.id] = {owner = payload.owner, spec = payload.spec, pos = payload.cf.Position, look = payload.cf.LookVector, seated = {}, net = payload.owner}
		return {ok = true}
	elseif op == "despawn" then Vessel.ships[payload.id] = nil; return true
	elseif op == "own" then return v ~= nil
	elseif op == "pose" then
		if not v then return nil end
		local seated = {}
		for k, role in pairs(v.seated) do seated[k] = role end
		return {position = v.pos, look = v.look, seated = seated, upY = 1, spin = 0, owner = v.net, holding = false}
	elseif op == "reset" then if v then v.pos = payload.cf.Position end return true
	elseif op == "seat" then if v then v.seated[payload.player] = payload.role end return v ~= nil
	elseif op == "unseat" then if v then v.seated[payload.player] = nil end return true
	elseif op == "state" or op == "fire" then return true end
	return nil
end}
local SHost = {open = 0, closed = {}, full = false, last = nil}
local shostFn = {Invoke = function(_, op, payload)
	if op == "open" then
		if SHost.full then return {ok = false, reason = "capacity"} end
		SHost.open += 1
		local center = Vector3.new(5000 + SHost.open * 400, 300, 0)
		SHost.last = {ok = true, fight = "story:" .. payload.uid .. ":" .. SHost.open, center = center, spawn = CFrame.new(center + Vector3.new(0, 4, -20)), lanterns = {}}
		return SHost.last
	elseif op == "close" then SHost.closed[payload.fight] = true; return true end
	return nil
end}
local CW -- the combat world (real logic) behind IsleStoryCombat
local SCombat = {spawned = {}, down = false}
local scombatFn = {Invoke = function(_, op, payload)
	if SCombat.down then error("combat down") end
	if op == "spawn" then
		local r = CW.logic.stRegister(payload.fight, payload.boss, {Name = payload.boss}, payload.center + Vector3.new(0, 3, 11), {members = payload.members, seed = payload.seed, center = payload.center, ground = payload.center.Y})
		if not r then return {ok = false} end
		SCombat.spawned[payload.fight] = r
		SCombat.seeds = SCombat.seeds or {}
		table.insert(SCombat.seeds, payload.seed)
		return {ok = true, hp = r.maxHp}
	elseif op == "status" then return CW.logic.lrStatus(payload.fight)
	elseif op == "despawn" then CW.logic.lrDespawn(payload.fight); return {ok = true} end
	return nil
end}
local storage = {IsleTravelGate = gate, IsleVesselHost = vesselFn, IsleStoryHost = shostFn, IsleStoryCombat = scombatFn}
local anchors = {}
local function place(name, pos) anchors[name] = {Name = "Anchor_" .. name, Parent = true, CFrame = CFrame.new(pos.X, pos.Y, pos.Z), Position = pos} end
local folder = {FindFirstChild = function(_, name) local key = string.match(name, "^Anchor_(.+)$"); return key and anchors[key] end}
local npcs = {}
local townsfolk = {GetChildren = function() return npcs end}
local ws = {}
ws.GetAttribute = function(self, k) return rawget(self, k) end
ws.SetAttribute = function(self, k, v) rawset(self, k, v) end
ws.FindFirstChild = function(_, name)
	if name == "Islands" then return folder end
	if name == "Townsfolk" then return townsfolk end
	if name == "AetherIsles" then return {FindFirstChild = function() return nil end} end
	return nil
end
local loops = {}
local H = luau.load("local __ws, __roblox, __storage, __loops = ...\n" .. prefix .. "\nreturn {player=player,cmd=cmd,data=data,advance=advance,services=services,objects=objects,allObjects=allObjects,closers=closers,Data=Data,clock=function() return clock end}",
	{debugName = "story-harness", injectGlobals = true})(ws, roblox, storage, loops)
local SD = H.Data
local SST = SD.Story
local SS = SD.Skysailing
local leaseHook
for _, o in ipairs(H.allObjects) do if o.Name == "IsleCoopProfile" then leaseHook = o end end
assert(leaseHook, "IsleCoopProfile")
local function renew(p) pcall(leaseHook.OnInvoke, p, true) end
local function state(p) renew(p); return H.cmd(p, "state") end
local function st(p) return state(p).story end
local function verb(p, v, item) renew(p); return H.cmd(p, v, item).message end
local function rootOf(p) return p.Character:FindFirstChild("HumanoidRootPart") end
local function humanoidOf(p) return p.Character:FindFirstChildOfClass("Humanoid") end
local function moveTo(p, pos) rootOf(p).Position = pos end
local function vp(t) return Vector3.new(t.x, t.y, t.z) end
local function use(p, action, item, region, pos)
	renew(p)
	moveTo(p, pos or Vector3.zero)
	local q = {Enabled = true, MaxActivationDistance = 9, GetAttribute = function(_, key)
		return ({IsleAction = action, IsleItem = item, IsleRegion = region})[key]
	end, FindFirstAncestorWhichIsA = function() return {Position = pos or Vector3.zero, CFrame = CFrame.new(pos or Vector3.zero)} end}
	H.advance(1)
	p.last = nil
	H.services.ProximityPromptService.PromptTriggered:Fire(q, p)
	return p.last and p.last.message, p.last
end
local function pivoted(p) p.Character.PivotTo = function(_, cf) rootOf(p).Position = cf.Position end end
local known = {}
local function join(id, mutate)
	local p = H.player(id)
	H.services.Players.PlayerRemoving:Fire(p)
	if mutate then mutate(H.data["p" .. id].profile) end
	local q = H.player(id)
	pivoted(q)
	known[q] = true
	return q
end
local function rejoin(p, mutate)
	H.services.Players.PlayerRemoving:Fire(p)
	if mutate then mutate(H.data["p" .. p.UserId].profile) end
	known[p] = nil
	local q = H.player(p.UserId)
	pivoted(q)
	known[q] = true
	return q
end
local function saved(p) return H.data["p" .. p.UserId].profile end
-- The combat world shares the harness players.
CW = world()
CW.list = {}
CW.logic = nil
do
	local w = CW
	w.logic = Combat.createLogic({
		Data = SD, Progression = P,
		now = function() return H.clock() end, time = function() return 5000 end, rng = function() return 0.5 end,
		players = function() return w.list end,
		alive = function(p) local h = humanoidOf(p); return h ~= nil and h.Health > 0 end,
		position = function(p) return rootOf(p).Position end,
		heal = function() end,
		bridge = function(op, player, payload)
			if op == "stats" then return {stats = {damage = 5000, strength = 300, critChance = 0, critDamage = 50, attackSpeed = 0}, combatLevel = 99, loadout = {style = "melee", levels = {}, supplies = {}}} end
			return nil
		end,
		lineOfSight = function() return true end,
	})
end
-- World layout: the cast and the set pieces.
local NPC_AT = {}
for i, c in ipairs(SST.Cast) do
	local pos = Vector3.new(i * 120, 0, 4000)
	NPC_AT[c.role] = pos
	table.insert(npcs, {GetAttribute = function(_, k) if k == "TownsfolkRole" then return c.role end return nil end,
		FindFirstChild = function(_, n) if n == "HumanoidRootPart" then return {Position = pos} end return nil end})
end
for i, piece in ipairs(SST.Pieces) do place("Story_" .. piece.id, Vector3.new(i * 90, 0, -4000)) end
for _, port in ipairs(SS.Ports) do place("Dock_" .. port.id, vp(port.landing)) end
local function pieceAt(id) return anchors["Story_" .. id].Position end
local function talkTo(p, role) moveTo(p, NPC_AT[role] + Vector3.new(3, 0, 0)); return verb(p, "storyTalk", role) end
local function cur(p) return st(p).cur end
local function lvl(n) return X[n] end
local function skills(pr, t) for k, v in pairs(t) do pr.xp[k] = lvl(v) end end
local function tick(p)
	H.advance(1)
	renew(p)
	for _, l in ipairs(loops) do
		if l.y == SS.TICK and coroutine.status(l.co) == "suspended" then
			local okR, y = coroutine.resume(l.co, SS.TICK)
			assert(okR, y)
			return
		end
	end
	error("the Skysailing loop was not found")
end

-- A fresh journal: chapter 1 waits behind its requirement.
local a = join(7101)
do
	local s = st(a)
	ok(s and s.cur and s.cur.ch == 1 and s.cur.step == 1, "a fresh journal starts at chapter 1, step 1")
	eq(s.qp, 0, "no story points yet")
	eq(#s.chapters, 8, "eight chapter rows")
	eq(s.chapters[1].status, "locked", "chapter 1 is locked behind two contracts")
	ok(s.chapters[1].reqs[1].met == false and has(s.chapters[1].reqs[1].text, "2 guild contracts"), "requirement row ✗")
	local m = talkTo(a, "StoryArchivist")
	ok(has(m, "requires") and has(m, "guild contracts"), "requirements gate the first talk: " .. tostring(m))
	eq(cur(a).step, 1, "still step 1")
	-- Spoofs: a talk from afar, the wrong NPC, an unknown role, a set piece without its prompt.
	a = rejoin(a, function(pr) pr.questCompleted = 2 end)
	eq(st(a).chapters[1].status, "available", "chapter 1 ready")
	moveTo(a, NPC_AT.StoryArchivist + Vector3.new(40, 0, 0))
	ok(has(verb(a, "storyTalk", "StoryArchivist"), "Find Sefa"), "talking needs the NPC in range")
	ok(has(talkTo(a, "StoryMiller"), "Brannick Tallow:"), "a different NPC just greets you")
	ok(has(verb(a, "storyTalk", "Banker"), "no one by that name"), "unknown story role refused")
	ok(has(verb(a, "storyInspect", "SkyTear"), "in person"), "inspect is prompt-only")
	ok(has(verb(a, "storyBoss", "Gloamwick"), "at its gate"), "storyBoss is prompt-only")
	ok(has((use(a, "storyBoss", "Gloamwick", nil, pieceAt("GloamGate"))), "sealed"), "a gate opens only on its step")
	eq(cur(a).step, 1, "no spoof moved the story")
	-- The real start.
	local before = st(a).cut
	local msg = talkTo(a, "StoryArchivist")
	ok(has(msg, "Sefa Lumenward:") and has(msg, "New objective"), "the first talk starts the chapter: " .. tostring(msg))
	local s = st(a)
	eq(s.cur.step, 2, "step 2")
	ok(s.cut and s.cut.id == "c1_intro" and (not before or s.cut.seq > before.seq), "the intro cutscene is named for the client")
	eq(s.chapters[1].status, "active", "chapter active")
	ok(s.cur.specs and s.cur.specs[1] == "npc:StoryMiller", "the next waypoint is Brannick")
	-- Order: the tear cannot be inspected before the wheat.
	ok(has((use(a, "storyInspect", "SkyTear", nil, pieceAt("SkyTear"))), "Nothing here"), "inspect out of order refused")
	talkTo(a, "StoryMiller")
	eq(cur(a).step, 3, "collect step")
	-- Collected before the step does not count: base is the lifetime total at the step.
	local base = saved(a) and 0
	a = rejoin(a, function(pr) pr.collection.Sunwheat = (pr.collection.Sunwheat or 0) + 12 end)
	local c = cur(a)
	ok(c.step == 3 and c.have == 12 and c.need == 20, "collection since the step (persisted base): " .. tostring(c.have))
	a = rejoin(a, function(pr) pr.collection.Sunwheat += 8 end)
	eq(cur(a).step, 4, "twenty sunwheat finish the step on their own")
	local _ = base
	ok(has((use(a, "storyInspect", "GlyphStone1", nil, pieceAt("GlyphStone1"))), "Nothing here"), "the wrong piece")
	local m4 = use(a, "storyInspect", "SkyTear", nil, pieceAt("SkyTear"))
	ok(has(m4, "New objective"), "the tear inspected: " .. tostring(m4))
	ok(has((use(a, "storyInspect", "SkyTear", nil, pieceAt("SkyTear"))), "Nothing here"), "a finished inspect step is closed")
	eq(st(a).cut.id, "c1_tear", "the tear cutscene")
	local coins, items = saved(a) and nil, nil
	local m5 = talkTo(a, "StoryArchivist")
	ok(has(m5, "Chapter complete") and has(m5, "+1 Quest Points"), "chapter 1 complete: " .. tostring(m5))
	s = st(a)
	eq(s.qp, 1, "1 story Quest Point")
	eq(#s.lamps, 1, "one lamp")
	eq(s.cur.ch, 2, "chapter 2 next")
	eq(s.chapters[1].status, "done", "chapter 1 ✓")
	local _ = coins, items
	-- Quest Points join the Journal total.
	local j = state(a).journal
	eq(j.questPoints, 2 + 1, "Journal QP = contracts + story")
	-- Repeating the finished talk never pays twice.
	local m6 = talkTo(a, "StoryArchivist")
	ok(not has(m6, "Chapter complete"), "no second reward")
	eq(st(a).qp, 1, "still 1 point")
end
-- Lamps: level-scaled, gated skills refused, consumed once.
do
	local petId
	for id in pairs(SD.PetById) do petId = petId or id end
	a = rejoin(a, function(pr) pr.xp.Mining = lvl(40); pr.pets = {{id = petId, level = 1, xp = 0}}; pr.activePet = 1 end)
	ok(has(verb(a, "storyLamp", "Carpentry"), "cannot train"), "no lamp XP for Carpentry")
	ok(has(verb(a, "storyLamp", "Gold"), "Choose a skill"), "unknown skill")
	local before = saved(a) and state(a).xp.Mining
	local m = verb(a, "storyLamp", "Mining")
	local expect = SST.lampXp(SST.Chapters[1].rewards.lamps[1].rate, 40)
	ok(has(m, "+" .. expect .. " Mining XP"), "lamp scales with level 40: " .. tostring(m))
	eq(state(a).xp.Mining - before, expect, "XP granted")
	eq(saved(a) and state(a).depth.pets[1].xp, 0, "[M4] a lamp is flat XP: the summoned pet earns nothing")
	ok(has(verb(a, "storyLamp", "Mining"), "no story XP lamps"), "a lamp is rubbed once")
end
-- The helper pin follows the story.
do
	local m = verb(a, "helperPin", "story")
	ok(has(m, "Pinned") and has(m, "The Brassbound Vault"), "pin the story: " .. tostring(m))
	local s = state(a)
	ok(s.systems.pin and s.systems.pin.id == "story", "systems pin")
	ok(has(a:GetAttribute("IsleObjectivePin"), "Mining level 20") or has(a:GetAttribute("IsleObjectivePin"), "Runebinding") or has(a:GetAttribute("IsleObjectivePin"), "Smithing"), "the sidebar shows the next requirement: " .. tostring(a:GetAttribute("IsleObjectivePin")))
	ok(st(a).pinned, "story.pinned")
end
-- Chapter 2: the rune lock (server-held, needs rubbings and runes).
do
	ok(has(talkTo(a, "StoryQuarrymaster"), "requires"), "chapter 2 gated")
	a = rejoin(a, function(pr) skills(pr, {Mining = 20, Runebinding = 10, Smithing = 15}) end)
	talkTo(a, "StoryQuarrymaster")
	eq(cur(a).step, 2, "craft step")
	a = rejoin(a, function(pr) pr.counters = pr.counters or {}; pr.counters.crafts = pr.counters.crafts or {}; pr.counters.crafts.BrassIngot = (pr.counters.crafts.BrassIngot or 0) + 5 end)
	eq(cur(a).step, 3, "crafts since the step finish it")
	-- The puzzle is closed until the rubbings are done.
	moveTo(a, pieceAt("BrassVault"))
	ok(has(verb(a, "storyPuzzle", "runelock:try"), "not part of your story"), "the lock before the rubbings")
	local sol = SST.runeSolution(SST.seedOf(a.UserId))
	for i = 1, 3 do
		local m = use(a, "storyInspect", "GlyphStone" .. i, nil, pieceAt("GlyphStone" .. i))
		ok(has(m, SD.Items[sol[i]].name), "rubbing " .. i .. " reveals its rune: " .. tostring(m))
	end
	-- A rejoin keeps the rubbings.
	a = rejoin(a)
	eq(cur(a).have, 3, "rubbings persist")
	use(a, "storyInspect", "GlyphStone4", nil, pieceAt("GlyphStone4"))
	local s = st(a)
	eq(s.cur.step, 4, "the lock step")
	ok(s.puzzle and s.puzzle.id == "runelock" and table.concat(s.puzzle.clue, ",") == table.concat(sol, ","), "the clue from the rubbings")
	-- Away from the vault: refused.
	moveTo(a, Vector3.new(0, 0, 0))
	ok(has(verb(a, "storyPuzzle", "runelock:set:1:" .. sol[1]), "Stand at"), "moves need the vault")
	moveTo(a, pieceAt("BrassVault"))
	ok(has(verb(a, "storyPuzzle", "runelock:try"), "all four"), "every dial first")
	ok(has(verb(a, "storyPuzzle", "runelock:solve"), "not a move"), "unknown move")
	ok(has(verb(a, "storyPuzzle", "stars:turn:1"), "not part of your story"), "another puzzle's move")
	-- Wrong order: lockout, nothing spent.
	a = rejoin(a, function(pr) for _, r in ipairs(SST.RUNES) do pr.items[r] = 3 end end)
	moveTo(a, pieceAt("BrassVault"))
	local wrong = {sol[2], sol[1], sol[3], sol[4]}
	for i, r in ipairs(wrong) do verb(a, "storyPuzzle", "runelock:set:" .. i .. ":" .. r) end
	ok(has(verb(a, "storyPuzzle", "runelock:try"), "Wrong order"), "a wrong answer is refused")
	eq(state(a).items[sol[1]], 3, "nothing spent on a wrong try")
	for i, r in ipairs(sol) do verb(a, "storyPuzzle", "runelock:set:" .. i .. ":" .. r) end
	ok(has(verb(a, "storyPuzzle", "runelock:try"), "spinning back"), "lockout after a wrong try")
	H.advance(SST.LOCK_LOCKOUT)
	-- Without the runes in the satchel: refused.
	a = rejoin(a, function(pr) pr.items[sol[3]] = 0 end)
	moveTo(a, pieceAt("BrassVault"))
	ok(has(verb(a, "storyPuzzle", "runelock:try"), "carry"), "the dials take real runes")
	eq(st(a).puzzle.s[1], sol[1], "dial settings persist across a rejoin")
	a = rejoin(a, function(pr) pr.items[sol[3]] = 1 end)
	moveTo(a, pieceAt("BrassVault"))
	local m = verb(a, "storyPuzzle", "runelock:try")
	ok(has(m, "lock sighs open") and has(m, "New objective"), "the lock opens: " .. tostring(m))
	eq(state(a).items[sol[3]], 0, "one of each rune spent")
	eq(state(a).items[sol[1]], 2, "one rune per dial")
	local done = talkTo(a, "StoryQuarrymaster")
	ok(has(done, "Brassbound Signet") and has(done, "+2 Quest Points"), "chapter 2 rewards: " .. tostring(done))
	eq(state(a).items.BrassboundSignet, 1, "the signet")
	ok(has(verb(a, "sell", "BrassboundSignet"), "bound to your journal"), "the signet cannot be sold")
	eq(st(a).qp, 3, "3 story points")
end
-- Chapter 3: the beacon (real Beaconry), the spiders, Gloamwick.
local function enterBoss(p, boss, region)
	local gate = SST.Pieces[(function() for i, piece in ipairs(SST.Pieces) do if piece.boss == boss then return i end end end)()]
	return use(p, "storyBoss", boss, region, pieceAt(gate.id))
end
do
	a = rejoin(a, function(pr) skills(pr, {Woodcutting = 30, Beaconry = 30, Mining = 30, Combat = 35}) end)
	talkTo(a, "StorySeer")
	eq(cur(a).kind, "beacon", "beacon step")
	-- Talking to Wick early does nothing.
	ok(not has(talkTo(a, "StoryWick"), "New objective"), "Wick waits for the beacon")
	a = rejoin(a, function(pr) pr.items.FlintStriker = 1; pr.items.EmberoakLog = 12 end)
	do
		-- [L3] a pyre fired from afar (stale prompt) never credits the step.
		local pyre = Vector3.new(-300, 0, -300)
		moveTo(a, pyre + Vector3.new(60, 0, 0))
		local q = {Enabled = true, MaxActivationDistance = 99, GetAttribute = function(_, key) return ({IsleAction = "beaconLight", IsleItem = "Windpine", IsleRegion = "Windpine"})[key] end,
			FindFirstAncestorWhichIsA = function() return {Position = pyre, CFrame = CFrame.new(pyre)} end}
		H.advance(1)
		renew(a)
		H.services.ProximityPromptService.PromptTriggered:Fire(q, a)
		eq(cur(a).kind, "beacon", "[L3] no credit away from the pyre")
	end
	local m = use(a, "beaconLight", "Windpine", "Windpine", Vector3.new(-300, 0, -300))
	ok(has(m, "blazes up"), "the Canopy Beacon is lit: " .. tostring(m))
	local s = st(a)
	eq(s.cur.kind, "talk", "lighting the beacon finished the step (" .. tostring(s.cur.kind) .. ")")
	talkTo(a, "StoryWick")
	eq(cur(a).kind, "kills", "spider step")
	a = rejoin(a, function(pr) pr.bestiary.GloomfangSpider = (pr.bestiary.GloomfangSpider or 0) + 8 end)
	s = st(a)
	eq(s.cur.kind, "boss", "boss step")
	eq(s.cut.id, "c3_gloam", "the boss cutscene")
	-- The gate needs its prompt and its region; a busy journal is refused.
	a:SetAttribute("LairBoss", "Bramblemaw")
	ok(has((enterBoss(a, "Gloamwick", "Gloomhollow")), "Finish your lair"), "busy players cannot enter")
	a:SetAttribute("LairBoss", "")
	SHost.full = true
	ok(has((enterBoss(a, "Gloamwick", "Gloomhollow")), "in use"), "no free hall: refused (fail closed)")
	SHost.full = false
	ok(has((enterBoss(a, "Vaelith", "Tempest")), "Tempest"), "another boss's gate is refused")
	-- Enter, then leave: nothing changes.
	local enter = enterBoss(a, "Gloamwick", "Gloomhollow")
	ok(has(enter, "domain"), "entered: " .. tostring(enter))
	ok((rootOf(a).Position - SHost.last.center).Magnitude < 30, "teleported into the arena")
	eq(a:GetAttribute(SST.FIGHT_FLAG), "Gloamwick", "StoryFight attribute")
	ok(a:GetAttribute("FastTravelAt") ~= nil, "server movement marked")
	ok(st(a).fight and st(a).fight.state == "warmup", "warmup")
	ok(has((enterBoss(a, "Gloamwick", "Gloomhollow")), "already inside"), "one encounter at a time")
	local fight1 = SHost.last.fight
	moveTo(a, SHost.last.center + Vector3.new(0, 0, -10))
	ok(has(verb(a, "storyLeave", nil), "left the encounter"), "leave")
	ok(SHost.closed[fight1], "the arena is torn down")
	eq(a:GetAttribute(SST.FIGHT_FLAG), "", "flag cleared")
	eq(cur(a).kind, "boss", "leaving keeps the step")
	ok(has(verb(a, "storyLeave", nil), "not inside"), "leave twice")
	-- Death ends the fight; the step stays; the gate reopens.
	enterBoss(a, "Gloamwick", "Gloomhollow")
	local center = SHost.last.center
	moveTo(a, center + Vector3.new(0, 0, -10))
	H.advance(SST.WARMUP + 1)
	ok(has(state(a).message, "rises"), "the boss rises after the warmup")
	ok(SCombat.spawned[SHost.last.fight] ~= nil, "combat spawned it")
	humanoidOf(a).Health = 0
	ok(has(state(a).message, "struck down"), "death ends the encounter")
	ok(SHost.closed[SHost.last.fight], "arena closed after death")
	ok(CW.logic.lrRecord(SHost.last.fight) == nil, "the boss despawned")
	humanoidOf(a).Health = 100
	eq(cur(a).kind, "boss", "a death keeps the step")
	-- Wandering out of the arena ends it too.
	enterBoss(a, "Gloamwick", "Gloomhollow")
	center = SHost.last.center
	local farAway = center + Vector3.new(200, 0, 0)
	moveTo(a, farAway)
	state(a)
	H.advance(SST.AWAY_SECONDS + 1)
	ok(has(state(a).message, "strayed"), "away from the arena")
	ok((rootOf(a).Position - farAway).Magnitude < 1, "[M1] an away timeout never teleports you back to the gate")
	-- [M1] a storyLeave while another activity holds the player never moves them.
	enterBoss(a, "Gloamwick", "Gloomhollow")
	local held = SHost.last.center + Vector3.new(0, 0, -10)
	moveTo(a, held)
	a:SetAttribute("LairBoss", "Bramblemaw")
	verb(a, "storyLeave", nil)
	ok((rootOf(a).Position - held).Magnitude < 1, "[M1] no move while LairBoss is set")
	a:SetAttribute("LairBoss", "")
	-- [M3] aboard a ship or seated: the gate refuses.
	a:SetAttribute("SailVessel", "9:helm")
	ok(has((enterBoss(a, "Gloamwick", "Gloomhollow")), "aboard a ship"), "[M3] storyBoss refused aboard a ship")
	a:SetAttribute("SailVessel", "")
	humanoidOf(a).SeatPart = {}
	ok(has((enterBoss(a, "Gloamwick", "Gloomhollow")), "Stand up"), "[M3] storyBoss refused while seated")
	humanoidOf(a).SeatPart = nil
	-- Disconnect mid-fight: torn down, no reward, rejoin finds the gate.
	enterBoss(a, "Gloamwick", "Gloomhollow")
	local f3 = SHost.last.fight
	moveTo(a, SHost.last.center + Vector3.new(0, 0, -10))
	H.advance(SST.WARMUP + 1)
	state(a)
	a = rejoin(a)
	ok(SHost.closed[f3] and CW.logic.lrRecord(f3) == nil, "a disconnect tears the fight down")
	eq(a:GetAttribute(SST.FIGHT_FLAG), nil, "a rejoin starts outside any encounter")
	eq(cur(a).kind, "boss", "the step waits")
	eq(st(a).fight, nil, "no fight after the rejoin")
	-- The win: shroud-aware strikes through the real combat logic, then the step advances once.
	CW.list = {a}
	enterBoss(a, "Gloamwick", "Gloomhollow")
	center = SHost.last.center
	moveTo(a, center + Vector3.new(0, 0, -10))
	H.advance(SST.WARMUP + 1)
	state(a)
	local r = SCombat.spawned[SHost.last.fight]
	ok(r and r.story, "the encounter record")
	CW.logic.beginTick(); CW.logic.lrTick(); CW.logic.endTick()
	local spot = SST.lanternSpots(r.def)[r.lit]
	moveTo(a, center + Vector3.new(spot.x, 0, spot.z))
	r.position = center + Vector3.new(spot.x, 3, spot.z + 3)
	H.advance(1)
	ok(CW.logic.attack(a, "attack", r.model), "a blow from the light lands")
	CW.logic.kill(r)
	humanoidOf(a).Health = 0 -- [L1] struck down after the killing blow: the kill is settled first
	local win = state(a).message
	humanoidOf(a).Health = 100
	ok(has(win, "defeated") and has(win, "New objective"), "the win advances the step: " .. tostring(win))
	ok(not has(win, "struck down"), "[L1] the win, not a death")
	eq(cur(a).kind, "talk", "talk to Wick")
	eq(st(a).fight, nil, "fight cleared")
	local again = state(a).message
	ok(not has(again, "defeated"), "the win is applied once")
	local done = talkTo(a, "StoryWick")
	ok(has(done, "Wickglass Lantern"), "chapter 3 rewards: " .. tostring(done))
	eq(st(a).cut.id, "c3_light", "the light cutscene named at the last step")
end
do
	local seeds, distinct = SCombat.seeds or {}, {}
	local n = 0
	for _, sd in ipairs(seeds) do if not distinct[sd] then distinct[sd] = true; n += 1 end end
	ok(#seeds >= 3 and n == #seeds, "[L7] every fight of the same journal gets its own seed (" .. n .. "/" .. #seeds .. ")")
end
-- Chapter 4: a real voyage to Tidewater.
do
	a = rejoin(a, function(pr) skills(pr, {Skysailing = 35, Fishing = 35}) end)
	talkTo(a, "StoryArchivist")
	eq(cur(a).kind, "sail", "sail step")
	ok(not has(talkTo(a, "StoryCaptain"), "New objective"), "Orla waits for your ship")
	a = rejoin(a, function(pr) pr.skysailing = SS.migrate({ship = SS.modelShip(35)}) end)
	-- [L2] a launch and a dock at the same port is no voyage.
	local TIDE = SS.PortById.Tidewater
	local m0 = use(a, "sailLaunch", "Tidewater", "Tidewater", vp(TIDE.landing))
	ok(has(m0, "helm"), "launched at Tidewater: " .. tostring(m0))
	tick(a); tick(a)
	ok(has(verb(a, "sailDock", nil), "Tidewater"), "docked at Tidewater")
	eq(cur(a).kind, "sail", "[L2] docking where you launched does not finish the sail step")
	H.advance(SS.LAUNCH_COOLDOWN + 1)
	local QUAY = SS.PortById.Quay
	local msg = use(a, "sailLaunch", "Quay", "Hub", vp(QUAY.landing))
	ok(has(msg, "helm"), "launched from the Quay: " .. tostring(msg))
	local id, ship
	for k, v in pairs(Vessel.ships) do if v.owner == a then id, ship = k, v end end
	ok(ship ~= nil, "the vessel")
	local target = vp(SS.PortById.Tidewater.berth)
	for _ = 1, 120 do
		local d = target - ship.pos
		local flat = Vector3.new(d.X, d.Y, d.Z)
		if flat.Magnitude < 0.5 then break end
		local stepLen = 14
		local move = if flat.Magnitude > stepLen then flat.Unit * stepLen else flat
		ship.pos = ship.pos + move
		ship.look = Vector3.new(move.X, 0, move.Z).Magnitude > 0.1 and Vector3.new(move.X, 0, move.Z).Unit or ship.look
		tick(a)
		if not Vessel.ships[id] then break end
	end
	tick(a); tick(a)
	ok(Vessel.ships[id] ~= nil, "the voyage stayed legal")
	local docked = verb(a, "sailDock", nil)
	ok(has(docked, "Tidewater"), "docked at Tidewater: " .. tostring(docked))
	eq(cur(a).kind, "talk", "docking finished the sail step")
	talkTo(a, "StoryCaptain")
	eq(st(a).cut.id, "c4_salt", "the salt cutscene")
	a = rejoin(a, function(pr) pr.collection.Lanternray = (pr.collection.Lanternray or 0) + 15 end)
	ok(has(talkTo(a, "StoryCaptain"), "Chapter complete"), "chapter 4 complete")
end
-- Chapter 5: the astrolabe (rings turned move by move).
local function solveStars(s)
	for code = 0, SST.STOPS ^ SST.RINGS - 1 do
		local c, x = {}, code
		for i = 1, SST.RINGS do c[i] = x % SST.STOPS; x //= SST.STOPS end
		local good = true
		for i = 1, SST.RINGS do
			local prev = if i == 1 then SST.RINGS else i - 1
			if (s[i] + c[i] + c[prev]) % SST.STOPS ~= 0 then good = false break end
		end
		if good then return c end
	end
	return nil
end
do
	a = rejoin(a, function(pr) skills(pr, {Runebinding = 25, Combat = 35}); pr.questCompleted = 6 end)
	talkTo(a, "StoryStargazer")
	a = rejoin(a, function(pr) pr.collection.StormFeather = (pr.collection.StormFeather or 0) + 12 end)
	local s = st(a)
	eq(s.cur.kind, "puzzle", "astrolabe step")
	a = rejoin(a, function(pr) pr.story.puzzle = nil end)
	s = st(a)
	ok(s.puzzle and s.puzzle.id == "stars", "[L4] a missing puzzle state is recreated")
	local start = table.clone(s.puzzle.s)
	ok(not SST.starSolved(start), "starts scrambled")
	moveTo(a, pieceAt("Astrolabe"))
	ok(has(verb(a, "storyPuzzle", "stars:turn:9"), "not a move"), "ring index checked")
	ok(has(verb(a, "storyPuzzle", "mirrors:turn:1"), "not part of your story"), "wrong puzzle")
	-- One turn, a rejoin keeps the rings.
	verb(a, "storyPuzzle", "stars:turn:1")
	a = rejoin(a)
	local mid = st(a).puzzle.s
	eq(mid[1], (start[1] + 1) % 8, "ring 1 turned and saved")
	eq(mid[2], (start[2] + 1) % 8, "its neighbour too")
	moveTo(a, pieceAt("Astrolabe"))
	verb(a, "storyPuzzle", "stars:reset")
	eq(table.concat(st(a).puzzle.s, ","), table.concat(start, ","), "reset restores the start")
	local c = solveStars(start)
	local last
	for i = 1, SST.RINGS do for _ = 1, c[i] do last = verb(a, "storyPuzzle", "stars:turn:" .. i) end end
	ok(has(last, "clicks into place"), "aligned through real moves: " .. tostring(last))
	eq(cur(a).kind, "talk", "puzzle step done")
	eq(st(a).cut.id, "c5_stars", "the stars cutscene")
	ok(has(talkTo(a, "StoryStargazer"), "Star-Chart Monocle"), "chapter 5")
end
-- Chapter 6: Vaelith; Quest Point gate.
do
	a = rejoin(a, function(pr) skills(pr, {Combat = 50}); pr.questCompleted = 0 end)
	local s = st(a)
	local qpRow
	for _, r in ipairs(s.chapters[6].reqs) do if has(r.text, "Quest Points") then qpRow = r end end
	ok(qpRow and qpRow.met == false, "chapter 6 waits on Quest Points (" .. tostring(qpRow and qpRow.have) .. ")")
	ok(has(talkTo(a, "StoryStormward"), "Quest Points"), "QP gate refuses")
	a = rejoin(a, function(pr) pr.questCompleted = 8 end)
	talkTo(a, "StoryStormward")
	a = rejoin(a, function(pr) pr.bestiary.TempestWraith = (pr.bestiary.TempestWraith or 0) + 10 end)
	eq(cur(a).kind, "boss", "Vaelith step")
	CW.list = {a}
	enterBoss(a, "Vaelith", "Tempest")
	local center = SHost.last.center
	moveTo(a, center + Vector3.new(0, 0, -8))
	H.advance(SST.WARMUP + 1)
	state(a)
	local r = SCombat.spawned[SHost.last.fight]
	r.position = center + Vector3.new(0, 3, -5)
	H.advance(1)
	ok(CW.logic.attack(a, "attack", r.model), "a blow lands on Vaelith")
	CW.logic.kill(r)
	-- A disconnect right after the kill is settled before the save.
	a = rejoin(a)
	eq(cur(a).kind, "talk", "a win at disconnect is kept (Story.depart)")
	ok(has(talkTo(a, "StoryStormward"), "Stormglass Pendant"), "chapter 6")
	eq(#st(a).lamps, 6, "lamps waiting (the chapter 1 lamp was rubbed)")
end
-- Chapter 7: the mirrors (posts are prompts too).
do
	a = rejoin(a, function(pr) skills(pr, {Fishing = 45, Skysailing = 40}) end)
	talkTo(a, "StoryCaptain")
	use(a, "storyInspect", "ShoalLens", "Tidewater", pieceAt("ShoalLens"))
	local s = st(a)
	eq(s.cur.kind, "puzzle", "mirror step")
	ok(s.puzzle.lit == false and #s.puzzle.path >= 1, "the beam path is published")
	local want
	for m = 0, 63 do
		local t = {}
		for i = 1, 6 do t[i] = (m // 2 ^ (i - 1)) % 2 end
		if SST.traceBeam(t) then want = t end
	end
	local last
	for i = 1, 6 do
		if s.puzzle.s[i] ~= want[i] then last = use(a, "storyPuzzle", "mirrors:turn:" .. i, "Tidewater", pieceAt("MirrorField")) end
	end
	ok(has(last, "clicks into place"), "the beam reaches the lens: " .. tostring(last))
	ok(has(talkTo(a, "StoryCaptain"), "Shoal-Light Charm"), "chapter 7")
end
-- Chapter 8: requirements incl. a quest; threads; Caedmon; the Loomheart.
do
	local blocked = talkTo(a, "StoryArchivist")
	ok(has(blocked, "requires"), "chapter 8 gated: " .. tostring(blocked))
	a = rejoin(a, function(pr) skills(pr, {Combat = 60, Runebinding = 40, Skysailing = 45}); for _, q in ipairs({"SurveyorsOath", "BrassfallEchoes", "WindpineVigil", "HollowLantern", "CrownOfTempest"}) do pr.questsDone[q] = true end; pr.questCompleted = 8 end)
	local s = st(a)
	eq(s.chapters[8].status, "available", "chapter 8 ready (QP " .. tostring(state(a).journal.questPoints) .. ")")
	ok(has(verb(a, "storyWarp", "Loomheart"), "finish The Sundered Sky"), "the Loomheart is locked until the end")
	talkTo(a, "StoryArchivist")
	talkTo(a, "StoryLoomwright")
	for i = 1, 3 do use(a, "storyInspect", "LoomThread" .. i, "ShatteredCrown", pieceAt("LoomThread" .. i)) end
	eq(cur(a).kind, "boss", "Caedmon step")
	CW.list = {a}
	enterBoss(a, "Caedmon", "ShatteredCrown")
	local center = SHost.last.center
	moveTo(a, center + Vector3.new(0, 0, -8))
	H.advance(SST.WARMUP + 1)
	state(a)
	local r = SCombat.spawned[SHost.last.fight]
	r.position = center + Vector3.new(0, 3, -5)
	H.advance(1)
	ok(CW.logic.attack(a, "attack", r.model), "a blow lands on Caedmon")
	CW.logic.kill(r)
	ok(has(state(a).message, "defeated"), "Caedmon falls")
	ok((rootOf(a).Position - pieceAt("SunderGate")).Magnitude < 10, "[M1] a win from inside the arena returns you to the gate")
	talkTo(a, "StoryLoomwright")
	local before = state(a)
	local qp0 = before.journal.questPoints
	local fin = talkTo(a, "StoryArchivist")
	ok(has(fin, "THE SUNDERED SKY IS COMPLETE") and has(fin, "Loomheart"), "the finale: " .. tostring(fin))
	s = st(a)
	ok(s.done and s.warps and s.warps.Loomheart, "done, warps open")
	eq(s.qp, 18, "18 story points")
	eq(state(a).journal.questPoints, qp0 + 4, "the last chapter's points join the total")
	eq(s.cut.id, "c8_mended", "the finale cutscene")
	eq(#s.unlocked, 11, "every cutscene can be replayed")
	eq(state(a).items.LoomwardenMantle, 1, "the mantle")
	eq(s.pinned, false, "a finished story unpins itself")
	ok(has(verb(a, "helperPin", "story"), "complete"), "pinning a finished story is refused")
	-- No talk or inspect after the end changes anything.
	local items = state(a).items.LoomwardenMantle
	talkTo(a, "StoryArchivist")
	use(a, "storyInspect", "LoomThread1", "ShatteredCrown", pieceAt("LoomThread1"))
	eq(state(a).items.LoomwardenMantle, items, "rewards once")
	-- Fast travel: gate, cooldown, region access, FastTravelAt.
	place("Story_Loomheart", Vector3.new(800, 120, -600))
	moveTo(a, Vector3.new(0, 0, 0))
	ok(has(verb(a, "storyWarp", "Loomheart"), "Stand at the Loomheart"), "[L8] no anywhere-teleport: only from a dais")
	moveTo(a, pieceAt("QuayLoom"))
	a:SetAttribute("SailVessel", "3:sails")
	ok(has(verb(a, "storyWarp", "Loomheart"), "aboard a ship"), "[M3] storyWarp refused aboard a ship")
	a:SetAttribute("SailVessel", "")
	local w = verb(a, "storyWarp", "Loomheart")
	ok(has(w, "Loomheart Terrace") and (rootOf(a).Position - Vector3.new(800, 124, -600)).Magnitude < 1, "the Loomheart carries you: " .. tostring(w))
	ok(has(verb(a, "storyWarp", "Quay"), "settling"), "warp cooldown")
	H.advance(SST.WARP_COOLDOWN + 1)
	moveTo(a, Vector3.new(800, 120, -600))
	storage.IsleTravelGate = nil
	ok(has(verb(a, "storyWarp", "Quay"), "will not open"), "no travel gate: fail closed")
	storage.IsleTravelGate = gate
	ok(has(verb(a, "storyWarp", "Quay"), "Loomstone"), "back to the Quay")
	ok(has(verb(a, "storyWarp", "Nowhere"), "Choose a destination"), "unknown destination")
	-- Persistence of the finished journal.
	a = rejoin(a)
	s = st(a)
	ok(s.done and s.qp == 18 and s.cur == nil, "a finished journal stays finished")
end
-- [L12] chapter rows are cached on (chapter, step, XP, quests, contracts) and still follow a change.
do
	local g = join(7106)
	local r1 = st(g).chapters[1]
	eq(r1.status, "locked", "[L12] locked")
	eq(st(g).chapters[1].status, "locked", "[L12] the cached row agrees")
	g = rejoin(g, function(pr) pr.questCompleted = 2 end)
	eq(st(g).chapters[1].status, "available", "[L12] a contract change rebuilds the rows")
	g = rejoin(g, function(pr) pr.xp.Mining = X[20]; pr.xp.Runebinding = X[10]; pr.xp.Smithing = X[15] end)
	local row = st(g).chapters[2]
	ok(row.reqs[1].met and row.reqs[2].met and row.reqs[3].met, "[L12] an XP change rebuilds the rows")
end
-- Migration and tampering at load.
do
	local b = join(7102, function(pr) pr.story = {v = 0, ch = 2, step = 3, marks = {GlyphStone1 = true, Bogus = true}, lamps = {{rate = 30}, {rate = 9999}}, base = -5} end)
	local s = st(b)
	eq(s.cur.ch, 2, "an older journal keeps its chapter")
	eq(s.cur.have, 1, "and its real marks")
	eq(#s.lamps, 1, "tampered lamps dropped")
	local pr = saved(b)
	ok(pr.story.v == SST.VERSION, "saved at the current version")
	local c = join(7103, function(pr2) pr2.story = "garbage" end)
	eq(st(c).cur.ch, 1, "garbage resets to chapter 1")
	-- A journal tampered to the end has no rewards it did not earn (items are not granted by migration).
	local d = join(7104, function(pr2) pr2.story = {ch = 9} end)
	ok(st(d).done and (state(d).items.LoomwardenMantle or 0) == 0, "migration never grants items")
	-- The lease: a journal that lost its lease cannot act.
	local _ = d
end
-- Shutdown: Story.drain settles a live win before the journals save.
do
	local e = join(7105, function(pr) pr.questCompleted = 8; pr.story = {ch = 3, step = 5}; skills(pr, {Combat = 60, Mining = 30}) end)
	CW.list = {e}
	enterBoss(e, "Gloamwick", "Gloomhollow")
	local center = SHost.last.center
	moveTo(e, center + Vector3.new(0, 0, -8))
	H.advance(SST.WARMUP + 1)
	state(e)
	local r = SCombat.spawned[SHost.last.fight]
	CW.logic.beginTick(); CW.logic.lrTick(); CW.logic.endTick()
	local spot = SST.lanternSpots(r.def)[r.lit]
	moveTo(e, center + Vector3.new(spot.x, 0, spot.z))
	r.position = center + Vector3.new(spot.x, 3, spot.z + 3)
	H.advance(1)
	ok(CW.logic.attack(e, "attack", r.model), "hit")
	CW.logic.kill(r)
	for _, f in ipairs(H.closers) do pcall(f) end
	eq(saved(e).story.step, 6, "the shutdown save carries the win")
end
print("Part C (server): " .. (checks - partC) .. " checks")

------------------------------------------------------------------------------
-- D. story.server.lua headless, the client and the registration
------------------------------------------------------------------------------
local partD = checks
do
	local Host
	local storageFolder = roblox.Instance.new("Folder")
	local hostEnv = {
		game = {GetService = function(_, name)
			if name == "ReplicatedStorage" then return {WaitForChild = function() return {} end} end
			if name == "ServerStorage" then return storageFolder end
			return {}
		end},
		workspace = roblox.Instance.new("Workspace"), Instance = roblox.Instance, Vector3 = Vector3, CFrame = CFrame, Color3 = roblox.Color3, Enum = roblox.Enum,
		require = function() return Data end,
		__StoryHostHarness = function(h) Host = h end,
	}
	luau.load(fs.readFile("story.server.lua"), {environment = hostEnv, injectGlobals = true})()
	ok(Host ~= nil, "the host loads headless")
	local root = roblox.Instance.new("Folder")
	local fights = {}
	for i = 1, ST.MAX_FIGHTS do
		local r = Host.open({uid = 100 + i, boss = ST.BossOrder[(i % 3) + 1]}, root)
		ok(r.ok and typeof(r.spawn) == "CFrame" and typeof(r.center) == "Vector3", "arena " .. i)
		ok((r.spawn.Position - r.center).Magnitude < ST.ARENA_RANGE, "the spawn is inside the arena range")
		fights[i] = r
	end
	eq(Host.open({uid = 1, boss = "Gloamwick"}, root).reason, "capacity", "arena cap")
	eq(Host.open({uid = 1, boss = "Nope"}, root).reason, "invalid", "unknown boss")
	-- Slots never overlap.
	for i = 1, #fights do for j = i + 1, #fights do ok((fights[i].center - fights[j].center).Magnitude >= 200, "arenas apart") end end
	-- A Gloamwick arena carries four lanterns at the data's spots; the exit prompt leaves.
	local g
	for _, f in ipairs(fights) do if f.lanterns then g = f end end
	ok(g and #g.lanterns == 4, "lantern parts")
	local spots = ST.lanternSpots(ST.Bosses.Gloamwick)
	for i, lamp in ipairs(g.lanterns) do
		local d = lamp.CFrame.Position - g.center
		ok(math.abs(d.X - spots[i].x) < 1e-3 and math.abs(d.Z - spots[i].z) < 1e-3, "lantern " .. i .. " at its spot")
	end
	local model = root:FindFirstChild(g.fight)
	local exitPrompt
	local parts = 0
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("ProximityPrompt") and obj:GetAttribute("IsleAction") == "storyLeave" then exitPrompt = obj end
		if obj:IsA("BasePart") then parts += 1; ok(obj.Anchored, "arena parts are anchored") end
		ok(not obj:IsA("Light"), "no server lights")
	end
	ok(exitPrompt ~= nil, "exit plinth prompt storyLeave")
	ok(parts <= 24, "arena stays light (" .. parts .. " parts)")
	ok(Host.close({fight = g.fight}) and root:FindFirstChild(g.fight) == nil, "close destroys the arena")
	ok(Host.close({fight = g.fight}), "close is idempotent")
	ok(Host.open({uid = 1, boss = "Gloamwick"}, root).ok, "a freed slot is reused")
	-- Set pieces on fake islands (no raycast: the island centre's height).
	local islands = roblox.Instance.new("Folder")
	local names = {}
	for _, piece in ipairs(ST.Pieces) do names[piece.isle] = true end
	for name in pairs(names) do
		local m = roblox.Instance.new("Model")
		m.Name = name
		m:SetAttribute("IslandCenter", Vector3.new(#name * 100, 20, 0))
		m.Parent = islands
	end
	local built = Host.placePieces(islands, nil)
	for _, piece in ipairs(ST.Pieces) do
		local m = built[piece.id]
		ok(m ~= nil, piece.id .. " built")
		local a = m:FindFirstChild("Anchor_Story_" .. piece.id)
		ok(a and a.Transparency == 1 and a.CanCollide == false, piece.id .. " anchor")
		local action, item, puzzle
		for _, obj in ipairs(m:GetDescendants()) do
			if obj:IsA("ProximityPrompt") and (obj:GetAttribute("IsleAction") ~= "storyPuzzle") then action, item, puzzle = obj:GetAttribute("IsleAction"), obj:GetAttribute("IsleItem"), obj:GetAttribute("StoryPuzzle") end
		end
		if piece.boss then eq(action, "storyBoss", piece.id .. " gate"); eq(item, piece.boss, piece.id .. " boss")
		elseif piece.warp then eq(action, "storyWarp", piece.id .. " warp")
		elseif piece.puzzle then eq(puzzle, piece.puzzle, piece.id .. " opens its puzzle panel (client)"); eq(action, nil, piece.id .. " study prompt is client-only")
		else eq(action, "storyInspect", piece.id .. " inspect"); eq(item, piece.id, piece.id .. " item") end
	end
	local mirrors = 0
	for _, obj in ipairs(built.MirrorField:GetDescendants()) do
		if obj:IsA("ProximityPrompt") and obj:GetAttribute("IsleAction") == "storyPuzzle" then mirrors += 1; ok(ST.parseMove(obj:GetAttribute("IsleItem")) ~= nil, "mirror prompt move parses") end
	end
	eq(mirrors, #ST.Mirror.mirrors, "a prompt on every signal mirror")
	local again = Host.placePieces(islands, nil)
	ok(next(again) == nil, "placement is idempotent")
end
do
	local client = fs.readFile("story.client.lua")
	ok(has(client, "ST.cutStep(") and has(client, "ST.cutStart("), "the client runs the shared runner")
	ok(has(client, "camera.CameraType = Enum.CameraType.Custom"), "restore returns the camera")
	ok(has(client, "local function restore()"), "one restore path")
	ok(not has(client, "SetCoreGuiEnabled") and not has(client, "WalkSpeed") and not has(client, "Anchored = true") and not has(client, "ContextActionService"), "a cutscene never takes the controls")
	local restores = select(2, client:gsub("restore%(%)", ""))
	ok(restores >= 5, "every ending restores (" .. restores .. " calls)")
	ok(has(client, "if not ok then") and has(client, "CharacterAdded:Connect(function() if S.run then restore() end end)"), "errors and respawns restore too")
	ok(has(client, "S.baseSeq = seq"), "a rejoin never replays the last cutscene")
	ok(select(2, client:gsub('make%("UIScale"', "")) >= 3 and has(client, "ViewportSize"), "[L9] UIScale on the panel, strip and title")
	ok(has(client, "not processed and (io.KeyCode == Enum.KeyCode.Backspace"), "[L10] typing never skips")
	ok(has(client, "S.pending = cut.id") and has(client, "ST.cutCalm("), "[L6] a named cutscene waits for calm")
	ok(has(client, "Cut.graceUntil"), "[L5] grace for the return-to-gate move")
	local server = fs.readFile("server.server.lua")
	local winAt = server:find('finish(player,p,"win")', 1, true)
	local advAt = winAt and server:find("advance(player,p)", winAt, true)
	ok(winAt and advAt and advAt - winAt < 200, "[L5] back at the gate before the step advances")
	ok(has(server, 'grantXp(p,skill,xp,"lectern")'), "[M4] lamps use the flat lectern source")
	ok(has(server, "for id,ready in pairs(Story.warpAt) do if ready<=now then Story.warpAt[id]=nil end end"), "[L10] warp cooldowns pruned")
	ok(has(server, '{"MinigameGame","LairBoss","RaidRun","RaidLobby",Data.Story.FIGHT_FLAG}'), "[M1] feat busy() knows story encounters")
	local _, lairBusy = server:gsub("local story=player:GetAttribute%(Data.Story.FIGHT_FLAG%)", "")
	eq(lairBusy, 2, "[M1] both lair / raid journal busy() checks know story encounters")
	ok(has(server, "if from==port then return end"), "[L2] dock credit needs another port")
	ok(has(fs.readFile("raids.server.lua"), 'player:GetAttribute("StoryFight")'), "[M1] raids busyElsewhere")
	local npcSrc = fs.readFile("npc.server.lua")
	local _, guards = npcSrc:gsub("Data.Story.travelBlock%(player%)", "")
	eq(guards, 2, "[M1 / M3] IsleTravelGate and the recall charm share the travel guard")
	ok(has(fs.readFile("story.server.lua"), "islands.ChildAdded:Connect"), "[L11] late islands get their pieces")
	ok(has(fs.readFile("story.server.lua"), "local ARENA_HALF = ST.ARENA_HALF"), "[M2] the arena uses ST.ARENA_HALF")
	local ui = fs.readFile("ui.client.lua")
	ok(has(ui, '"Confirm · "..skill'), "[L10] lamp rub confirm step")
	ok(has(ui, '"Story"') and has(ui, "function Pages.drawStory()") and has(ui, "storyLamp=true") and has(ui, "UI.checklist(body,nextOrder,\"REQUIREMENTS\""), "Journal › Story with ✓/✗ requirements")
	local anim = fs.readFile("animate.client.lua")
	for _, v in ipairs({"storyInspect", "storyPuzzle", "storyBoss", "storyLeave", "storyWarp"}) do ok(has(anim, v .. " = "), v .. " has a gesture") end
	local project = fs.readFile("default.project.json")
	ok(has(project, '"Story": { "$path": "story.server.lua" }') and has(project, '"IsleStory": { "$path": "story.client.lua" }'), "project wiring")
	local verify = fs.readFile("verify.luau")
	ok(has(verify, 'Story = "story.server.lua"') and has(verify, 'IsleStory = "story.client.lua"'), "verify.luau bindings")
	for _, script in ipairs({"scripts/build.sh", "build.ps1"}) do ok(has(fs.readFile(script), "verify-story.luau"), script .. " runs this suite") end
	local server = fs.readFile("server.server.lua")
	ok(has(server, 'verb=="storyTalk"') and has(server, "Story.depart") and has(server, "Story.drain"), "server hooks")
	ok(has(fs.readFile("docs/DEPTH-CONTRACT.md"), "## 53. The Sundered Sky"), "contract §53")
end
print("Part D (host, client, wiring): " .. (checks - partD) .. " checks")
print(string.format("The Sundered Sky QA passed %d checks.", checks))
print("SUITE-END verify-story.luau")
