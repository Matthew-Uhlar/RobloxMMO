-- Gestures: procedural swing and interact animations. See docs/DEPTH-CONTRACT.md §10.
-- No uploaded animation assets exist, so every gesture is a short list of
-- keyframed joint poses (degrees + studs, torso space) sampled with easing and
-- written to the character's Motor6D.Transform after the default Animate
-- script has run (RunService.Stepped), blended by a fade weight. When a gesture
-- ends the weight fades to zero, so the Animator's own pose is back in charge.
--
-- Layout:
--   1. Core   – pure, Roblox-light rules: easing, pose sampling, rig mapping,
--               gesture table, prompt → gesture selection, tool models, the
--               engine state machine and remote admission. Tested headlessly by
--               verify-gesture.luau through the __GestureTestHarness hook.
--   2. Runtime – prompts, the IsleGesture relay, held tool parts, impact FX.
--
-- Triggers (local player):
--   * ProximityPrompt hold begins  → gesture loops (strikes) while held.
--   * Hold ends / prompt triggers  → the current strike finishes, then it ends.
--   * Instant prompt (no hold)     → one strike.
--   * IsleUpdate message for a consumed item → eat / drink.
--   * ReplicatedStorage.IsleGestureLocal (client-side BindableEvent created
--     here): :Fire(name, target?, itemId?) lets other client scripts (combat,
--     UI) play a gesture; combat.client.lua routes its attack swing through it.
-- Replication: IsleGesture:FireServer(name, targetPart?, itemId?) – the server
-- (gesture.server.lua) validates and re-broadcasts (source, name, target, itemId)
-- to nearby clients. Purely cosmetic: nothing here touches gameplay state.

------------------------------------------------------------------------------
-- 1. Core
------------------------------------------------------------------------------
local Core = {}
Core.FADE_IN = 0.08
Core.FADE_OUT = 0.14
Core.REMOTE_CAP = 12 -- most remote characters animated at once (nearest win)
Core.REMOTE_RANGE = 100 -- remote gestures farther than this from us are skipped
Core.MAX_FX_PARTS = 80

local rad = math.rad

Core.ease = {
	linear = function(a) return a end,
	quadIn = function(a) return a * a end,
	quadOut = function(a) return 1 - (1 - a) * (1 - a) end,
	quadInOut = function(a) return if a < 0.5 then 2 * a * a else 1 - (-2 * a + 2) ^ 2 / 2 end,
	sineInOut = function(a) return -(math.cos(math.pi * a) - 1) / 2 end,
	backOut = function(a)
		local c1 = 1.70158
		return 1 + (c1 + 1) * (a - 1) ^ 3 + c1 * (a - 1) ^ 2
	end,
}

-- Logical joints. Each pose entry is {rx, ry, rz, x, y, z}: degrees about the
-- parent part's axes (+rx raises an arm forward / leans a torso back, +ry turns
-- toward the character's left, +rz swings a right arm outward) and a stud offset.
Core.JOINTS = {"rightArm", "rightElbow", "rightWrist", "leftArm", "leftElbow", "waist", "neck", "root",
	"rightHip", "leftHip", "rightKnee", "leftKnee"}

-- Motor name → the logical joints composed onto it (and their strength). R6 has
-- no elbows or knees: half the elbow bend folds into the shoulder, and the waist
-- rides on the RootJoint with the crouch offset damped so legs stay near ground.
Core.RIGS = {
	R15 = {
		{"RightShoulder", {{"rightArm", 1}}}, {"RightElbow", {{"rightElbow", 1}}}, {"RightWrist", {{"rightWrist", 1}}},
		{"LeftShoulder", {{"leftArm", 1}}}, {"LeftElbow", {{"leftElbow", 1}}},
		{"Waist", {{"waist", 1}}}, {"Neck", {{"neck", 1}}}, {"Root", {{"root", 1}}},
		{"RightHip", {{"rightHip", 1}}}, {"LeftHip", {{"leftHip", 1}}}, {"RightKnee", {{"rightKnee", 1}}}, {"LeftKnee", {{"leftKnee", 1}}},
	},
	R6 = {
		{"Right Shoulder", {{"rightArm", 1}, {"rightElbow", 0.5}}}, {"Left Shoulder", {{"leftArm", 1}, {"leftElbow", 0.5}}},
		{"Neck", {{"neck", 1}}}, {"RootJoint", {{"root", 0.4}, {"waist", 0.6}}},
		{"Right Hip", {{"rightHip", 0.6}}}, {"Left Hip", {{"leftHip", 0.6}}},
	},
}
Core.HAND = {R15 = "RightHand", R6 = "Right Arm"}
Core.LEFT_HAND = {R15 = "LeftHand", R6 = "Left Arm"}

local ZERO = {0, 0, 0, 0, 0, 0}

-- Samples keyframes {t, ease, pose, mark} at time t. Joints absent from a
-- keyframe are at rest (zero). Returns joint → {6 numbers}.
function Core.samplePose(keys, t)
	local first = keys[1]
	if t <= first.t then
		local out = {}
		for joint, v in pairs(first.pose) do out[joint] = table.clone(v) end
		return out
	end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b.t then
			local span = b.t - a.t
			local alpha = if span > 0 then (t - a.t) / span else 1
			alpha = (Core.ease[b.ease or "quadInOut"] or Core.ease.quadInOut)(math.clamp(alpha, 0, 1))
			local out = {}
			for _, joint in ipairs(Core.JOINTS) do
				local pa, pb = a.pose[joint], b.pose[joint]
				if pa or pb then
					pa, pb = pa or ZERO, pb or ZERO
					local v = table.create(6, 0)
					for k = 1, 6 do
						local x, y = pa[k] or 0, pb[k] or 0
						v[k] = x + (y - x) * alpha
					end
					out[joint] = v
				end
			end
			return out
		end
	end
	local out = {}
	for joint, v in pairs(keys[#keys].pose) do out[joint] = table.clone(v) end
	return out
end

function Core.jointCFrame(v, scale)
	scale = scale or 1
	return CFrame.new((v[4] or 0) * scale, (v[5] or 0) * scale, (v[6] or 0) * scale)
		* CFrame.Angles(rad((v[1] or 0) * scale), rad((v[2] or 0) * scale), rad((v[3] or 0) * scale))
end

-- A rotation R (plus offset) expressed in the parent part's space, converted
-- into the motor's own frame: Part0 * C0 * T must equal Part0 * pivot * R * C0r,
-- so T = C0r⁻¹ · R · C0r. R15 C0s are axis-aligned (T = R); R6's are rotated.
function Core.basisOf(c0)
	return c0 - c0.Position
end
function Core.toJointSpace(r, basis)
	return basis:Inverse() * r * basis
end

-- Poses -------------------------------------------------------------------
local function merge(base, extra)
	local out = table.clone(base)
	for k, v in pairs(extra or {}) do out[k] = v end
	return out
end
local function key(t, pose, ease, mark) return {t = t, pose = pose, ease = ease, mark = mark} end
local REST = {}

local MINE_READY = {rightArm = {55, 0, 10}, rightElbow = {40}, leftArm = {50, -25, -10}, leftElbow = {45}, waist = {-6, 15, 0}}
local MINE_UP = {rightArm = {168, 0, 12}, rightElbow = {30}, leftArm = {155, -15, -8}, leftElbow = {28}, waist = {10, 10, 0}, neck = {-4}}
local MINE_HIT = {rightArm = {35, 0, 5}, rightElbow = {8}, leftArm = {35, -15, -5}, leftElbow = {12}, waist = {-22, 5, 0}, neck = {-10}}

local CHOP_READY = {rightArm = {75, -10, 0}, rightElbow = {20}, leftArm = {65, -35, 0}, leftElbow = {35}}
local CHOP_BACK = {rightArm = {82, -75, 0}, rightElbow = {35}, leftArm = {65, -70, 0}, leftElbow = {50}, waist = {0, -28, 0}}
local CHOP_HIT = {rightArm = {80, 30, 0}, rightElbow = {5}, leftArm = {70, 15, 0}, leftElbow = {15}, waist = {-6, 22, 0}}

local FISH_HOLD = {rightArm = {68, 0, 6}, rightElbow = {22}, leftArm = {30, -20, -6}, leftElbow = {30}}
local FISH_BACK = {rightArm = {160, 0, 10}, rightElbow = {45}, waist = {10, -12, 0}, leftArm = {20, 0, -10}}
local FISH_CAST = {rightArm = {78, 0, 5}, rightElbow = {4}, waist = {-12, 0, 0}, leftArm = {30, -15, -8}, leftElbow = {20}}
local FISH_DIP = {rightArm = {60, 0, 6}, rightElbow = {28}, leftArm = {30, -20, -6}, leftElbow = {30}}
local FISH_REEL = {rightArm = {132, 0, 6}, rightElbow = {55}, leftArm = {70, -30, -6}, leftElbow = {70}, waist = {8, 0, 0}}

local CROUCH = {root = {0, 0, 0, 0, -0.9, 0}, rightHip = {62}, leftHip = {40}, rightKnee = {-82}, leftKnee = {-70},
	waist = {-30, 0, 0}, neck = {14}}
local HARVEST_REACH = merge(CROUCH, {rightArm = {70}, rightElbow = {10}, leftArm = {70}, leftElbow = {10}})
local HARVEST_GRAB = merge(CROUCH, {rightArm = {42}, rightElbow = {0}, leftArm = {42}, leftElbow = {0}, waist = {-40, 0, 0}})
local HARVEST_PULL = merge(CROUCH, {rightArm = {96, 0, 10}, rightElbow = {72}, leftArm = {96, 0, -10}, leftElbow = {72}, waist = {-14, 0, 0}})

local HAMMER_READY = {rightArm = {60, 0, 10}, rightElbow = {50}, leftArm = {40, -20, -10}, leftElbow = {60}, waist = {-10, 0, 0}}
local HAMMER_UP = merge(HAMMER_READY, {rightArm = {132, 0, 15}, rightElbow = {72}, waist = {-4, 0, 0}})
local HAMMER_HIT = merge(HAMMER_READY, {rightArm = {44, 0, 5}, rightElbow = {28}, waist = {-18, 0, 0}})

local STIR_BASE = {rightElbow = {40}, leftArm = {35, -15, -12}, leftElbow = {50}, waist = {-12, 0, 0}}
local function stirAt(ry, rz, rx) return merge(STIR_BASE, {rightArm = {rx or 55, ry, rz}}) end

local FLIP_READY = {rightArm = {60, 0, 5}, rightElbow = {50}, leftArm = {30, -10, -8}, leftElbow = {40}, waist = {-8, 0, 0}}
local FLIP_DIP = merge(FLIP_READY, {rightArm = {46, 0, 5}, rightElbow = {62}})
local FLIP_FLICK = merge(FLIP_READY, {rightArm = {88, 0, 5}, rightElbow = {18}})

local SAW_BACK = {rightArm = {50, 0, 6}, rightElbow = {75}, leftArm = {55, -30, -5}, leftElbow = {40}, waist = {-16, 0, 0}}
local SAW_PUSH = merge(SAW_BACK, {rightArm = {76, 0, 4}, rightElbow = {6}, waist = {-22, 0, 0}})

local REACH = {rightArm = {86, -10, 0}, rightElbow = {16}, waist = {-6, 0, 0}, neck = {-8}}
local PRESS = {rightArm = {78, -10, 0}, rightElbow = {4}, waist = {-8, 0, 0}, neck = {-8}}

local EAT_UP = {rightArm = {70, 30, 0}, rightElbow = {112}, neck = {-4}}
local EAT_BITE = {rightArm = {74, 32, 0}, rightElbow = {118}, neck = {-12}}
local DRINK_UP = {rightArm = {76, 25, 0}, rightElbow = {116}, neck = {18}}
local DRINK_TIP = {rightArm = {86, 25, 0}, rightElbow = {122}, neck = {26}}

-- Combat styles. Bow (left hand): raise, draw the string to the cheek, loose.
local BOW_RAISE = {leftArm = {88, 12, 0}, leftElbow = {4}, rightArm = {80, 30, 0}, rightElbow = {50}, waist = {0, -18, 0}, neck = {0, 14, 0}}
local BOW_DRAW = {leftArm = {90, 14, 0}, leftElbow = {0}, rightArm = {92, 52, 0}, rightElbow = {128}, waist = {0, -26, 0}, neck = {-4, 20, 0}}
local BOW_LOOSE = {leftArm = {90, 14, 0}, leftElbow = {0}, rightArm = {96, 20, 30}, rightElbow = {30}, waist = {0, -22, 0}, neck = {-4, 18, 0}}
-- Staff (two hands): raise overhead, then thrust it forward to release.
local STAFF_RAISE = {rightArm = {150, 0, 12}, rightElbow = {30}, leftArm = {140, -20, -10}, leftElbow = {40}, waist = {8, 0, 0}, neck = {10}}
local STAFF_THRUST = {rightArm = {98, 0, 6}, rightElbow = {6}, leftArm = {92, -25, -6}, leftElbow = {22}, waist = {-12, 0, 0}, neck = {-6}}
-- Wand: a quick wrist flick from the shoulder.
local WAND_UP = {rightArm = {120, -15, 10}, rightElbow = {60}, rightWrist = {-30}}
local WAND_FLICK = {rightArm = {84, 10, 4}, rightElbow = {8}, rightWrist = {35}, waist = {-6, 0, 0}}
-- Heal: both hands raised to the sky, chin up.
local HEAL_UP = {rightArm = {165, 0, 22}, rightElbow = {12}, leftArm = {165, 0, -22}, leftElbow = {12}, waist = {10, 0, 0}, neck = {22}}

-- Agility (AgilityMove player attribute; the server moves the anchored root,
-- these only pose the limbs). Legs are driven too: the root is anchored, so the
-- Animator's fall/idle pose underneath is replaced while the move runs.
local CLIMB_A = {rightArm = {168, 0, 12}, rightElbow = {18}, leftArm = {118, 0, -12}, leftElbow = {70}, waist = {8, 0, 0}, neck = {12},
	rightHip = {58}, rightKnee = {-78}, leftHip = {12}, leftKnee = {-24}}
local CLIMB_B = {rightArm = {118, 0, 12}, rightElbow = {70}, leftArm = {168, 0, -12}, leftElbow = {18}, waist = {8, 0, 0}, neck = {12},
	rightHip = {12}, rightKnee = {-24}, leftHip = {58}, leftKnee = {-78}}
local BALANCE_A = {rightArm = {6, 0, 84}, rightElbow = {6}, leftArm = {6, 0, -78}, leftElbow = {6}, waist = {0, 0, -6}, neck = {-10},
	rightHip = {24}, rightKnee = {-12}, leftHip = {-14}, leftKnee = {-6}}
local BALANCE_B = {rightArm = {6, 0, 78}, rightElbow = {6}, leftArm = {6, 0, -84}, leftElbow = {6}, waist = {0, 0, 6}, neck = {-10},
	rightHip = {-14}, rightKnee = {-6}, leftHip = {24}, leftKnee = {-12}}
local SWING_GRIP = {rightArm = {176, 0, 6}, rightElbow = {12}, leftArm = {176, 0, -6}, leftElbow = {12}, neck = {10}}
local SWING_BACK = merge(SWING_GRIP, {rightHip = {-28}, leftHip = {-22}, rightKnee = {-40}, leftKnee = {-46}, waist = {12, 0, 0}})
local SWING_FORE = merge(SWING_GRIP, {rightHip = {62}, leftHip = {56}, rightKnee = {-12}, leftKnee = {-8}, waist = {-8, 0, 0}})
local LEDGE_A = {rightArm = {42, 0, 72}, rightElbow = {28}, leftArm = {38, 0, -64}, leftElbow = {32}, waist = {-6, 0, 0}, neck = {0, -30, 0},
	rightHip = {0, 0, 18}, leftHip = {0, 0, -4}}
local LEDGE_B = {rightArm = {38, 0, 64}, rightElbow = {32}, leftArm = {42, 0, -72}, leftElbow = {28}, waist = {-6, 0, 0}, neck = {0, -30, 0},
	rightHip = {0, 0, 4}, leftHip = {0, 0, -18}}
local LEAP_LOAD = {rightArm = {-40, 0, 12}, leftArm = {-40, 0, -12}, waist = {-24, 0, 0}, rightHip = {54}, leftHip = {54}, rightKnee = {-80}, leftKnee = {-80}}
local LEAP_AIR = {rightArm = {150, 0, 20}, rightElbow = {20}, leftArm = {150, 0, -20}, leftElbow = {20}, waist = {-6, 0, 0},
	rightHip = {70}, leftHip = {24}, rightKnee = {-30}, leftKnee = {-96}}
local LEAP_TUCK = merge(LEAP_AIR, {rightHip = {78}, leftHip = {36}, rightKnee = {-48}, leftKnee = {-100}})
local VAULT_PLANT = {rightArm = {58, 0, 12}, rightElbow = {4}, leftArm = {58, 0, -12}, leftElbow = {4}, waist = {-28, 0, 0},
	rightHip = {70, 0, 30}, leftHip = {66, 0, 26}, rightKnee = {-30}, leftKnee = {-40}}
local VAULT_OVER = merge(VAULT_PLANT, {rightArm = {28, 0, 14}, leftArm = {28, 0, -14}, waist = {-10, 0, 0}, rightHip = {80, 0, 40}, leftHip = {78, 0, 36}})
local ZIP_A = {rightArm = {178, 0, 4}, rightElbow = {8}, leftArm = {176, 0, -4}, leftElbow = {10}, neck = {14},
	rightHip = {18}, leftHip = {12}, rightKnee = {-14}, leftKnee = {-10}}
local ZIP_B = merge(ZIP_A, {rightHip = {8}, leftHip = {20}, rightKnee = {-8}, leftKnee = {-18}, waist = {4, 0, 0}})
local DROP_SIT = {rightArm = {-24, 0, 26}, rightElbow = {10}, leftArm = {-24, 0, -26}, leftElbow = {10}, waist = {16, 0, 0}, neck = {-12},
	rightHip = {84}, leftHip = {80}, rightKnee = {-14}, leftKnee = {-10}}
local DROP_RIDE = merge(DROP_SIT, {waist = {22, 0, 0}, rightArm = {-30, 0, 30}, leftArm = {-30, 0, -30}})
local FALL_A = {rightArm = {150, 0, 50}, rightElbow = {30}, leftArm = {100, 0, -70}, leftElbow = {20}, waist = {16, 0, 8}, neck = {20},
	rightHip = {40}, rightKnee = {-60}, leftHip = {-20}, leftKnee = {-20}}
local FALL_B = {rightArm = {100, 0, 70}, rightElbow = {20}, leftArm = {150, 0, -50}, leftElbow = {30}, waist = {16, 0, -8}, neck = {20},
	rightHip = {-20}, rightKnee = {-20}, leftHip = {40}, leftKnee = {-60}}
-- Hunter: set a trap (crouch, hands to the ground) and swing a net.
local NET_BACK = {rightArm = {150, -40, 10}, rightElbow = {30}, leftArm = {40, -20, -10}, leftElbow = {40}, waist = {4, -26, 0}, neck = {0, 10, 0}}
local NET_SWEEP = {rightArm = {96, 46, 0}, rightElbow = {8}, leftArm = {30, 10, -10}, leftElbow = {30}, waist = {-10, 24, 0}}

-- Gesture table. intro/loop/outro are keyframe lists; the loop repeats while
-- the prompt is held (and at least minCycles times). marks fire impact FX.
-- tool = held model kind; skill = which snapshot tool colours it.
Core.GESTURES = {
	mine = {tool = "Pickaxe", skill = "Mining", fx = "chips", shake = true,
		intro = {key(0, REST), key(0.12, MINE_READY, "quadOut")},
		loop = {key(0, MINE_READY), key(0.24, MINE_UP, "quadOut"), key(0.34, MINE_HIT, "quadIn", "impact"), key(0.56, MINE_READY, "sineInOut")},
		outro = {key(0, MINE_READY), key(0.18, REST, "quadInOut")}},
	chop = {tool = "Hatchet", skill = "Woodcutting", fx = "wood", shake = true,
		intro = {key(0, REST), key(0.12, CHOP_READY, "quadOut")},
		loop = {key(0, CHOP_READY), key(0.22, CHOP_BACK, "quadOut"), key(0.32, CHOP_HIT, "quadIn", "impact"), key(0.52, CHOP_READY, "sineInOut")},
		outro = {key(0, CHOP_READY), key(0.18, REST, "quadInOut")}},
	fish = {tool = "Rod", skill = "Fishing", fx = "splash", minCycles = 0,
		intro = {key(0, REST), key(0.3, FISH_BACK, "quadOut"), key(0.45, FISH_CAST, "quadIn", "cast"), key(0.7, FISH_HOLD, "sineInOut")},
		loop = {key(0, FISH_HOLD), key(0.45, FISH_DIP, "sineInOut", "bob"), key(0.9, FISH_HOLD, "sineInOut")},
		outro = {key(0, FISH_HOLD), key(0.25, FISH_REEL, "backOut", "reel"), key(0.55, REST, "quadInOut")}},
	harvest = {tool = "Hoe", skill = "Farming", fx = "dust",
		intro = {key(0, REST), key(0.2, HARVEST_REACH, "quadOut")},
		loop = {key(0, HARVEST_REACH), key(0.26, HARVEST_GRAB, "quadIn", "impact"), key(0.52, HARVEST_PULL, "backOut"), key(0.7, HARVEST_REACH, "sineInOut")},
		outro = {key(0, HARVEST_REACH), key(0.25, REST, "quadInOut")}},
	hammer = {tool = "Hammer", fx = "sparks", shake = true,
		intro = {key(0, REST), key(0.12, HAMMER_READY, "quadOut")},
		loop = {key(0, HAMMER_READY), key(0.2, HAMMER_UP, "quadOut"), key(0.28, HAMMER_HIT, "quadIn", "impact"), key(0.48, HAMMER_READY, "sineInOut")},
		outro = {key(0, HAMMER_READY), key(0.16, REST, "quadInOut")}},
	stir = {tool = "Ladle", fx = "bubbles",
		intro = {key(0, REST), key(0.15, stirAt(15, 0), "quadOut")},
		loop = {key(0, stirAt(15, 0)), key(0.22, stirAt(0, 14, 50), "sineInOut"), key(0.45, stirAt(-15, 0), "sineInOut", "impact"),
			key(0.67, stirAt(0, -10, 60), "sineInOut"), key(0.9, stirAt(15, 0), "sineInOut")},
		outro = {key(0, stirAt(15, 0)), key(0.18, REST, "quadInOut")}},
	flip = {tool = "Pan", fx = "steam",
		intro = {key(0, REST), key(0.12, FLIP_READY, "quadOut")},
		loop = {key(0, FLIP_READY), key(0.18, FLIP_DIP, "quadInOut"), key(0.3, FLIP_FLICK, "backOut", "impact"), key(0.62, FLIP_READY, "sineInOut")},
		outro = {key(0, FLIP_READY), key(0.16, REST, "quadInOut")}},
	saw = {tool = "Saw", fx = "sawdust",
		intro = {key(0, REST), key(0.14, SAW_BACK, "quadOut")},
		loop = {key(0, SAW_BACK), key(0.28, SAW_PUSH, "quadInOut", "impact"), key(0.56, SAW_BACK, "quadInOut")},
		outro = {key(0, SAW_BACK), key(0.16, REST, "quadInOut")}},
	interact = {fx = "ring",
		loop = {key(0, REST), key(0.2, REACH, "quadOut"), key(0.3, PRESS, "quadIn", "impact"), key(0.55, REST, "quadInOut")}},
	attack = {tool = "Sword", variants = {
		{key(0, REST), key(0.1, {rightArm = {90, -62, 0}, rightElbow = {30}, waist = {0, -22, 0}}, "quadOut"),
			key(0.2, {rightArm = {88, 52, 0}, rightElbow = {6}, waist = {-4, 22, 0}}, "quadIn", "impact"), key(0.38, REST, "quadInOut")},
		{key(0, REST), key(0.1, {rightArm = {92, 58, 0}, rightElbow = {60}, waist = {0, 20, 0}}, "quadOut"),
			key(0.2, {rightArm = {86, -60, 0}, rightElbow = {6}, waist = {-4, -22, 0}}, "quadIn", "impact"), key(0.38, REST, "quadInOut")},
		{key(0, REST), key(0.12, {rightArm = {170, 0, 10}, rightElbow = {40}, waist = {8, 0, 0}}, "quadOut"),
			key(0.22, {rightArm = {40, 0, 4}, rightElbow = {6}, waist = {-16, 0, 0}}, "quadIn", "impact"), key(0.4, REST, "quadInOut")},
	}},
	eat = {tool = "Food", fx = "crumbs",
		loop = {key(0, REST), key(0.25, EAT_UP, "quadOut"), key(0.38, EAT_BITE, "quadIn", "impact"), key(0.52, EAT_UP),
			key(0.66, EAT_BITE, "quadIn", "impact"), key(1.0, REST, "quadInOut")}},
	drink = {tool = "Flask",
		loop = {key(0, REST), key(0.3, DRINK_UP, "quadOut"), key(0.75, DRINK_TIP, "sineInOut", "impact"), key(1.0, REST, "quadInOut")}},
	-- Combat styles (combat.client.lua): bow shot, staff cast, wand flick, Mend.
	shoot = {tool = "Bow", hand = "left",
		loop = {key(0, REST), key(0.12, BOW_RAISE, "quadOut"), key(0.3, BOW_DRAW, "quadInOut"), key(0.36, BOW_LOOSE, "quadOut", "release"),
			key(0.6, REST, "quadInOut")}},
	cast = {tool = "Staff", fx = "ring",
		loop = {key(0, REST), key(0.18, STAFF_RAISE, "quadOut"), key(0.32, STAFF_THRUST, "backOut", "impact"), key(0.62, REST, "quadInOut")}},
	flick = {tool = "Wand", fx = "ring",
		loop = {key(0, REST), key(0.1, WAND_UP, "quadOut"), key(0.18, WAND_FLICK, "quadIn", "impact"), key(0.4, REST, "quadInOut")}},
	heal = {fx = "mend",
		loop = {key(0, REST), key(0.25, HEAL_UP, "backOut", "impact"), key(0.7, HEAL_UP), key(0.95, REST, "quadInOut")}},
	-- Agility moves (attribute-driven, see Core.agilityGesture): durations
	-- stretch to AgilityMoveDuration through Core.timing (whole loops, scaled).
	climb = {agility = true,
		intro = {key(0, REST), key(0.16, CLIMB_A, "quadOut")},
		loop = {key(0, CLIMB_A), key(0.34, CLIMB_B, "sineInOut"), key(0.68, CLIMB_A, "sineInOut")},
		outro = {key(0, CLIMB_A), key(0.2, REST, "quadInOut")}},
	balance = {agility = true,
		intro = {key(0, REST), key(0.2, BALANCE_A, "quadOut")},
		loop = {key(0, BALANCE_A), key(0.4, BALANCE_B, "sineInOut"), key(0.8, BALANCE_A, "sineInOut")},
		outro = {key(0, BALANCE_A), key(0.2, REST, "quadInOut")}},
	swing = {agility = true,
		intro = {key(0, REST), key(0.2, SWING_GRIP, "quadOut")},
		loop = {key(0, SWING_GRIP), key(0.3, SWING_BACK, "sineInOut"), key(0.75, SWING_FORE, "sineInOut"), key(1.0, SWING_GRIP, "sineInOut")},
		outro = {key(0, SWING_GRIP), key(0.22, REST, "quadInOut")}},
	ledge = {agility = true,
		intro = {key(0, REST), key(0.18, LEDGE_A, "quadOut")},
		loop = {key(0, LEDGE_A), key(0.35, LEDGE_B, "sineInOut"), key(0.7, LEDGE_A, "sineInOut")},
		outro = {key(0, LEDGE_A), key(0.2, REST, "quadInOut")}},
	leap = {agility = true,
		intro = {key(0, REST), key(0.16, LEAP_LOAD, "quadOut"), key(0.3, LEAP_AIR, "backOut")},
		loop = {key(0, LEAP_AIR), key(0.25, LEAP_TUCK, "sineInOut"), key(0.5, LEAP_AIR, "sineInOut")},
		outro = {key(0, LEAP_AIR), key(0.14, LEAP_LOAD, "quadIn"), key(0.34, REST, "quadOut")}},
	vault = {agility = true,
		intro = {key(0, REST), key(0.16, VAULT_PLANT, "quadOut")},
		loop = {key(0, VAULT_PLANT), key(0.3, VAULT_OVER, "sineInOut"), key(0.6, VAULT_PLANT, "sineInOut")},
		outro = {key(0, VAULT_PLANT), key(0.24, REST, "quadInOut")}},
	zip = {agility = true,
		intro = {key(0, REST), key(0.2, ZIP_A, "quadOut")},
		loop = {key(0, ZIP_A), key(0.45, ZIP_B, "sineInOut"), key(0.9, ZIP_A, "sineInOut")},
		outro = {key(0, ZIP_A), key(0.22, REST, "quadInOut")}},
	drop = {agility = true,
		intro = {key(0, REST), key(0.2, DROP_SIT, "quadOut")},
		loop = {key(0, DROP_SIT), key(0.3, DROP_RIDE, "sineInOut"), key(0.6, DROP_SIT, "sineInOut")},
		outro = {key(0, DROP_SIT), key(0.24, REST, "quadInOut")}},
	fall = {agility = true,
		intro = {key(0, REST), key(0.1, FALL_A, "quadOut")},
		loop = {key(0, FALL_A), key(0.15, FALL_B, "sineInOut"), key(0.3, FALL_A, "sineInOut")},
		outro = {key(0, FALL_A), key(0.16, REST, "quadInOut")}},
	-- Hunter: crouch to set or collect a trap; sweep a net through a swarm.
	settrap = {fx = "dust",
		intro = {key(0, REST), key(0.2, HARVEST_REACH, "quadOut")},
		loop = {key(0, HARVEST_REACH), key(0.3, HARVEST_GRAB, "quadIn", "impact"), key(0.6, HARVEST_REACH, "sineInOut")},
		outro = {key(0, HARVEST_REACH), key(0.25, REST, "quadInOut")}},
	netswing = {tool = "Net", fx = "ring",
		loop = {key(0, REST), key(0.16, NET_BACK, "quadOut"), key(0.32, NET_SWEEP, "quadIn", "impact"), key(0.62, REST, "quadInOut")}},
}
Core.NAMES = {}
for name in pairs(Core.GESTURES) do Core.NAMES[name] = true end

-- AgilityMove "<anim>:<seq>" -> gesture name, seq ("" or unknown -> nil).
Core.AGILITY = {climb = "climb", balance = "balance", swing = "swing", ledge = "ledge", leap = "leap", vault = "vault",
	zip = "zip", drop = "drop", fall = "fall"}
function Core.agilityGesture(value)
	if type(value) ~= "string" then return nil end
	local anim, seq = string.match(value, "^(%a+):(%d+)$")
	local name = anim and Core.AGILITY[anim]
	if not name then return nil end
	return name, tonumber(seq)
end
-- Fit a gesture to `duration` seconds: whole loops between intro and outro,
-- played at `rate` (virtual seconds per real second) so it ends on time.
function Core.timing(def, duration)
	local intro = if def.intro then Core.duration(def.intro) else 0
	local outro = if def.outro then Core.duration(def.outro) else 0
	local loop = Core.duration(Core.keysFor(def, "loop", 1))
	duration = math.max(0.2, tonumber(duration) or 0)
	local loops = math.max(1, math.floor((duration - intro - outro) / loop + 0.5))
	local natural = intro + loops * loop + outro
	return loops, natural / duration
end


function Core.keysFor(def, phase, variant)
	if phase == "loop" and def.variants then
		return def.variants[((variant or 1) - 1) % #def.variants + 1]
	end
	return def[phase]
end
function Core.duration(keys) return keys[#keys].t end

-- Prompt → gesture -----------------------------------------------------------
Core.SKILL_GESTURE = {Mining = "mine", Woodcutting = "chop", Fishing = "fish", Farming = "harvest"}
Core.COOP_GESTURE = {Timber = "chop", Ore = "mine", Herb = "harvest"}
Core.STATION_GESTURE = {Forge = {"hammer"}, Cauldron = {"stir"}, Hearth = {"flip", "stir"}, Workbench = {"hammer", "saw"}, Slayer = {"interact"},
	-- Crafting stations (prompt action "craftStation"): Jeweller's Bench, Tanning Rack, Glass Furnace.
	Jeweller = {"hammer"}, Tannery = {"saw", "hammer"}, Glassworks = {"stir"}}
Core.ACTION_GESTURE = {fight = "attack", worker = "hammer", workerBuild = "hammer", decorate = "hammer", trap = "settrap", net = "netswing"}
-- Agility prompts animate from the AgilityMove attribute the server sets instead.
Core.SILENT_ACTION = {agility = true, shortcut = true}

-- info = {action, item, coopResource}; counter alternates station variants.
function Core.selectGesture(info, Data, counter)
	local action, item = info.action, info.item
	if Core.SILENT_ACTION[action] then return nil end
	if info.coopResource and Core.COOP_GESTURE[info.coopResource] then return Core.COOP_GESTURE[info.coopResource] end
	if action == "gather" and type(item) == "string" then
		local skill = Data.ResourceSkill[item]
		return Core.SKILL_GESTURE[skill] or "interact"
	end
	if (action == "station" or action == "craftStation") and Core.STATION_GESTURE[item] then
		local list = Core.STATION_GESTURE[item]
		return list[((counter or 0) % #list) + 1]
	end
	if action == "craft" then
		local recipe = Data.Recipes and Data.Recipes[item]
		local station = recipe and recipe.station
		if item == "Tonic" or station == "Cauldron" then return "stir" end
		if station == "Hearth" then return "flip" end
		return "hammer"
	end
	return Core.ACTION_GESTURE[action] or "interact"
end

-- Snapshot message after a successful consume → eat / drink + item id.
function Core.consumeGesture(message, Data)
	if type(message) ~= "string" or message == "" then return nil end
	for id, def in pairs(Data.Items) do
		if def.kind == "consumable" then
			for _, label in ipairs({def.name, id}) do
				if type(label) == "string" and message:sub(1, #label + 1) == label .. " " then
					local rest = message:sub(#label + 2)
					if rest:find("^restored up to") or rest:find("^active for") then
						local drink = def.category == "potion" or id == "Tonic" or (def.name or ""):find("Tonic") ~= nil
							or (def.name or ""):find("Cocoa") ~= nil
						return if drink then "drink" else "eat", id
					end
				end
			end
		end
	end
	return nil
end

-- Held tools -----------------------------------------------------------------
Core.WOOD = "8A5A32"
Core.BARE_METAL = "8C8478" -- no tool owned yet: a worn stone/iron head
Core.TOOL_ITEM_KIND = {mine = "Pickaxe", chop = "Hatchet", fish = "Rod", harvest = "Hoe"}

local function hex(h)
	h = tostring(h or "FFFFFF")
	return Color3.fromRGB(tonumber(h:sub(1, 2), 16) or 255, tonumber(h:sub(3, 4), 16) or 255, tonumber(h:sub(5, 6), 16) or 255)
end
Core.hex = hex

-- Colour of the working head of the gesture's tool. itemId is the player's best
-- tool for the skill (snapshot depth.tools[skill]), weapon, or consumed item.
function Core.toolColor(Data, gesture, itemId)
	local def = type(itemId) == "string" and Data.Items[itemId]
	if def and Core.itemFits(gesture, def) then return hex(def.color) end
	return hex(Core.BARE_METAL)
end
-- Weapon style a combat gesture's held model shows (bows / staves and wands).
Core.STYLE_GESTURE = {shoot = "ranged", cast = "magic", flick = "magic"}
function Core.itemFits(gesture, def)
	local kind = Core.TOOL_ITEM_KIND[gesture]
	if kind then return def.kind == "tool" and def.toolKind == kind end
	if gesture == "attack" then return def.kind == "weapon" end
	if Core.STYLE_GESTURE[gesture] then return def.kind == "weapon" and def.style == Core.STYLE_GESTURE[gesture] end
	if gesture == "eat" or gesture == "drink" then return def.kind == "consumable" end
	return false
end

-- Part specs in the grip frame (hand bottom; the handle runs along -Z, the
-- swing plane is YZ). {name, size, offset, colour key, material, shape}
function Core.toolSpec(kind)
	local W, H = "wood", "head"
	local function p(name, size, offset, colour, material, shape)
		return {name = name, size = size, offset = offset, colour = colour, material = material or "Metal", shape = shape}
	end
	local V = Vector3.new
	local specs = {
		Pickaxe = {p("Handle", V(0.22, 0.22, 3), V(0, 0, -1.2), W, "Wood"), p("Head", V(0.3, 2, 0.32), V(0, 0, -2.55), H),
			p("Spike", V(0.2, 0.5, 0.2), V(0, -1.15, -2.55), H)},
		Hatchet = {p("Handle", V(0.22, 0.22, 2.6), V(0, 0, -1), W, "Wood"), p("Blade", V(0.15, 0.9, 0.75), V(0, 0.4, -2.05), H)},
		Rod = {p("Grip", V(0.24, 0.24, 1.2), V(0, 0, -0.3), W, "Wood"), p("Rod", V(0.12, 0.12, 5), V(0, 0, -3.4), H),
			p("Reel", V(0.4, 0.4, 0.4), V(0, -0.28, -0.2), H, "Metal", "Ball")},
		Hoe = {p("Handle", V(0.2, 0.2, 3.2), V(0, 0, -1.3), W, "Wood"), p("Blade", V(0.7, 0.9, 0.12), V(0, -0.4, -2.85), H)},
		Hammer = {p("Handle", V(0.2, 0.2, 1.6), V(0, 0, -0.5), W, "Wood"), p("Head", V(0.42, 0.9, 0.42), V(0, 0, -1.25), H)},
		Ladle = {p("Handle", V(0.16, 0.16, 2.2), V(0, 0, -0.8), W, "Wood"), p("Bowl", V(0.6, 0.6, 0.6), V(0, -0.25, -1.95), H, "Wood", "Ball")},
		Pan = {p("Handle", V(0.18, 0.18, 1), V(0, 0, -0.2), W, "Wood"), p("Pan", V(1.4, 0.14, 1.4), V(0, 0, -1.35), H)},
		Saw = {p("Handle", V(0.3, 0.6, 0.5), V(0, 0, -0.1), W, "Wood"), p("Blade", V(0.06, 0.7, 2.4), V(0, -0.1, -1.6), H)},
		Sword = {p("Grip", V(0.2, 0.2, 0.9), V(0, 0, 0), W, "Wood"), p("Guard", V(0.9, 0.18, 0.18), V(0, 0, -0.5), H),
			p("Blade", V(0.12, 0.32, 3.2), V(0, 0, -2.2), H)},
		Food = {p("Food", V(0.6, 0.5, 0.6), V(0, 0, -0.35), H, "SmoothPlastic", "Ball")},
		Flask = {p("Flask", V(0.45, 0.7, 0.45), V(0, 0.15, -0.3), H, "Glass"), p("Cork", V(0.2, 0.2, 0.2), V(0, 0.6, -0.3), W, "Wood")},
		-- Held in the left hand: limbs run along the grip axis (vertical with the
		-- arm raised), tinted by the bow's wood tier; a pale string behind them.
		Bow = {p("Grip", V(0.26, 0.26, 0.6), V(0, 0, 0), W, "Wood"), p("UpperLimb", V(0.18, 0.2, 2.1), V(0, 0.18, -1.3), H, "Wood"),
			p("LowerLimb", V(0.18, 0.2, 2.1), V(0, 0.18, 1.3), H, "Wood"), p("String", V(0.04, 0.04, 4.6), V(0, 0.55, 0), "string", "SmoothPlastic")},
		-- Two-handed staff: a long shaft through the grip, a tier-tinted orb and cradle.
		Staff = {p("Shaft", V(0.22, 0.22, 5.2), V(0, 0, -0.9), W, "Wood"), p("Cradle", V(0.5, 0.5, 0.3), V(0, 0, -3.5), W, "Wood"),
			p("Orb", V(0.62, 0.62, 0.62), V(0, 0, -3.85), H, "Neon", "Ball")},
		Wand = {p("Rod", V(0.12, 0.12, 1.5), V(0, 0, -0.6), W, "Wood"), p("Tip", V(0.26, 0.26, 0.26), V(0, 0, -1.4), H, "Neon", "Ball")},
		-- Hunter's net: a long pole, a hoop and a pale mesh.
		Net = {p("Pole", V(0.18, 0.18, 3.2), V(0, 0, -1.3), W, "Wood"), p("Hoop", V(1.5, 0.12, 0.12), V(0, 0, -2.95), H),
			p("Mesh", V(1.3, 1.1, 0.06), V(0, -0.55, -3.0), "string", "Fabric")},
	}
	return specs[kind]
end

-- Impact point: the point of the target's box nearest the hand.
function Core.impactPoint(targetPos, targetSize, handPos)
	local half = targetSize / 2
	return Vector3.new(
		math.clamp(handPos.X, targetPos.X - half.X, targetPos.X + half.X),
		math.clamp(handPos.Y, targetPos.Y - half.Y, targetPos.Y + half.Y),
		math.clamp(handPos.Z, targetPos.Z - half.Z, targetPos.Z + half.Z))
end

-- FX budget per impact; reduced motion keeps a soft puff and no shake.
function Core.fxBudget(reduced) return if reduced then 2 else 7 end
function Core.shouldShake(reduced, def, isLocal) return isLocal and not reduced and def.shake == true end

-- Remote admission: active = {[key] = distance}. Returns admit, keyToEvict.
function Core.admitRemote(active, key, distance, cap, range)
	cap, range = cap or Core.REMOTE_CAP, range or Core.REMOTE_RANGE
	if distance > range then return false end
	if active[key] ~= nil then return true end
	local count, farKey, farDist = 0, nil, -1
	for k, d in pairs(active) do
		count += 1
		if d > farDist then farKey, farDist = k, d end
	end
	if count < cap then return true end
	if distance < farDist then return true, farKey end
	return false
end

-- Rig binding ------------------------------------------------------------------
function Core.rigType(character)
	if character:FindFirstChild("UpperTorso") then return "R15" end
	if character:FindFirstChild("Torso") then return "R6" end
	return nil
end
function Core.bindRig(character)
	local kind = Core.rigType(character)
	if not kind then return nil end
	local entries = {}
	for _, spec in ipairs(Core.RIGS[kind]) do
		local motor = character:FindFirstChild(spec[1], true)
		if motor and motor:IsA("Motor6D") then
			table.insert(entries, {motor = motor, parts = spec[2], basis = Core.basisOf(motor.C0)})
		end
	end
	return entries, kind
end
-- Joints a gesture ever poses (any key of intro, loop, variants, outro). Only
-- motors driving one of them are touched: writing identity Transforms to the
-- rest (hips, knees, root on a mining swing) at full weight would freeze the
-- Animator's walk cycle underneath the gesture.
function Core.drivenJoints(def)
	local joints = {}
	local function scan(keys)
		for _, k in ipairs(keys or {}) do
			for joint in pairs(k.pose or {}) do joints[joint] = true end
		end
	end
	scan(def.intro); scan(def.loop); scan(def.outro)
	for _, keys in ipairs(def.variants or {}) do scan(keys) end
	return joints
end
function Core.drivenRig(rig, def)
	local joints, out = Core.drivenJoints(def), {}
	for _, entry in ipairs(rig) do
		for _, part in ipairs(entry.parts) do
			if joints[part[1]] then table.insert(out, entry); break end
		end
	end
	return out
end
function Core.motorTarget(entry, pose)
	local r = CFrame.new()
	for _, part in ipairs(entry.parts) do
		local v = pose[part[1]]
		if v then r = r * Core.jointCFrame(v, part[2]) end
	end
	return Core.toJointSpace(r, entry.basis)
end

-- Engine -------------------------------------------------------------------
-- deps: now(), alive(character), attachTool(character, kind, colour) -> handle
-- with :Destroy(), watch(character, onEnd) -> {connections}, mark(state, mark),
-- cycle(state) (a new loop strike while held).
-- Which hand a gesture's model is held in ("left" for the bow).
function Core.handFor(def, rigKind)
	local map = if def and def.hand == "left" then Core.LEFT_HAND else Core.HAND
	return map[rigKind]
end
function Core.createEngine(deps)
	local E = {active = {}, count = 0}
	local function remove(character, abrupt)
		local s = E.active[character]
		if not s then return end
		E.active[character] = nil
		E.count -= 1
		for _, c in ipairs(s.conns or {}) do c:Disconnect() end
		s.conns = nil
		if s.tool then s.tool:Destroy(); s.tool = nil end
		if abrupt and s.weight > 0.01 then
			for _, entry in ipairs(s.rig) do entry.motor.Transform = CFrame.new() end
		end
		s.finished = true
	end
	function E.stop(character) remove(character, true) end
	function E.get(character) return E.active[character] end
	function E.play(character, name, opts)
		opts = opts or {}
		local def = Core.GESTURES[name]
		if not def or not deps.alive(character) then return nil end
		local current = E.active[character]
		if current and current.name == name and not current.fadeStart and opts.extend then
			current.extra += 1
			return current
		end
		if current then remove(character, false) end
		local rig = deps.bindRig(character)
		rig = rig and Core.drivenRig(rig, def)
		if not rig or #rig == 0 then return nil end
		local now = deps.now()
		local s = {character = character, name = name, def = def, rig = rig, holding = opts.hold == true, extra = 0, cycles = 0,
			target = opts.target, variant = opts.variant or 1, start = now, phaseStart = now, lastT = -1, weight = 0,
			phase = if def.intro then "intro" else "loop", isLocal = opts.isLocal == true, info = opts.info, rate = 1}
		-- Timed (agility moves): a fixed number of loops, scaled to end on time.
		if opts.duration then s.loops, s.rate = Core.timing(def, opts.duration) end
		E.active[character] = s
		E.count += 1
		if def.tool then s.tool = deps.attachTool(character, def.tool, opts.color, def.hand) end
		s.conns = deps.watch(character, function() E.stop(character) end) or {}
		return s
	end
	function E.release(character)
		local s = E.active[character]
		if s then s.holding = false end
	end
	local function wantsLoop(s)
		if s.loops then return s.cycles < s.loops end
		local minCycles = s.def.minCycles or 1
		return s.holding or s.extra > 0 or s.cycles < minCycles
	end
	local function nextPhase(s, now, dur)
		s.phaseStart += dur
		s.lastT = -1
		if s.phase == "intro" then
			s.phase = if wantsLoop(s) then "loop" else (if s.def.outro then "outro" else "done")
		elseif s.phase == "loop" then
			s.cycles += 1
			if wantsLoop(s) then
				if not s.holding and s.extra > 0 and s.cycles >= (s.def.minCycles or 1) then s.extra -= 1 end
				if s.def.variants then s.variant += 1 end
				if s.holding and deps.cycle then deps.cycle(s) end
			else
				s.phase = if s.def.outro then "outro" else "done"
			end
		elseif s.phase == "outro" then
			s.phase = "done"
		end
		if s.phase == "done" then s.fadeStart = now end
	end
	function E.step()
		if E.count == 0 then return end
		local real = deps.now()
		for character, s in pairs(E.active) do
			-- Per-gesture clock: timed gestures run at s.rate from their start.
			local now = s.start + (real - s.start) * s.rate
			if not deps.alive(character) then
				remove(character, true)
				continue
			end
			local keys, guard = nil, 0
			while s.phase ~= "done" and guard < 4 do
				guard += 1
				keys = Core.keysFor(s.def, s.phase, s.variant)
				local dur = Core.duration(keys)
				local t = now - s.phaseStart
				local upto = math.min(t, dur)
				for _, k in ipairs(keys) do
					if k.mark and k.t > s.lastT and k.t <= upto then deps.mark(s, k.mark) end
				end
				s.lastT = upto
				if t < dur then break end
				s.lastPose = keys[#keys].pose
				nextPhase(s, now, dur)
			end
			local pose, weight
			if s.phase == "done" then
				weight = 1 - (now - s.fadeStart) / Core.FADE_OUT
				if weight <= 0 then
					remove(character, false)
					continue
				end
				pose = s.lastPose or REST
			else
				pose = Core.samplePose(keys, now - s.phaseStart)
				weight = math.min(1, (now - s.start) / Core.FADE_IN)
			end
			s.weight = weight
			for _, entry in ipairs(s.rig) do
				local target = Core.motorTarget(entry, pose)
				entry.motor.Transform = entry.motor.Transform:Lerp(target, weight)
			end
		end
	end
	function E.clear()
		for character in pairs(E.active) do remove(character, true) end
	end
	return E
end

if __GestureTestHarness then
	__GestureTestHarness(Core)
	return
end

------------------------------------------------------------------------------
-- 2. Runtime
------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local Data = require(ReplicatedStorage:WaitForChild("AetherData"))
local relay = ReplicatedStorage:WaitForChild("IsleGesture")

-- Latest snapshot facts used for colours (purely cosmetic).
local bestTools, weaponId = {}, nil
local stationCounter = 0

local function reducedMotion() return player:GetAttribute("ReducedMotion") == true end

local function humanoidOf(character)
	return character and character:FindFirstChildOfClass("Humanoid")
end
local function alive(character)
	if not character or not character.Parent then return false end
	local humanoid = humanoidOf(character)
	return humanoid ~= nil and humanoid.Health > 0
end

-- Held tool: parts welded to the hand for the gesture's lifetime.
local function attachTool(character, kind, colour, side)
	local rigKind = Core.rigType(character)
	local hand = rigKind and character:FindFirstChild(Core.handFor({hand = side}, rigKind))
	local specs = Core.toolSpec(kind)
	if not hand or not specs then return nil end
	local grip = hand:FindFirstChild(if side == "left" then "LeftGripAttachment" else "RightGripAttachment")
	local gripC0 = if grip then CFrame.new(grip.Position) else CFrame.new(0, -hand.Size.Y / 2, 0)
	local model = Instance.new("Model")
	model.Name = "IsleGestureTool"
	for _, spec in ipairs(specs) do
		local part = Instance.new("Part")
		part.Name = spec.name
		part.Size = spec.size
		part.Shape = if spec.shape == "Ball" then Enum.PartType.Ball else Enum.PartType.Block
		part.Material = Enum.Material[spec.material] or Enum.Material.Metal
		part.Color = if spec.colour == "head" then (colour or Core.hex(Core.BARE_METAL))
			elseif spec.colour == "string" then Core.hex("EDE6D2") else Core.hex(Core.WOOD)
		part.CanCollide, part.CanQuery, part.CanTouch, part.Massless, part.CastShadow = false, false, false, true, false
		if spec.material == "Glass" then part.Transparency = 0.25 end
		part.CFrame = hand.CFrame * gripC0 * CFrame.new(spec.offset)
		local weld = Instance.new("Weld")
		weld.Part0, weld.Part1 = hand, part
		weld.C0 = gripC0 * CFrame.new(spec.offset)
		weld.Parent = part
		part.Parent = model
	end
	model.Parent = character
	return model
end

local function watch(character, onEnd)
	local humanoid = humanoidOf(character)
	local conns = {
		character.AncestryChanged:Connect(function(_, parent) if not parent then onEnd() end end),
		-- Equipping a real Tool takes over the hand: end the gesture.
		character.ChildAdded:Connect(function(child) if child:IsA("Tool") then onEnd() end end),
	}
	if humanoid then
		table.insert(conns, humanoid.Died:Connect(onEnd))
		table.insert(conns, humanoid.Seated:Connect(function(seated) if seated then onEnd() end end))
	end
	return conns
end

-- Impact FX: small anchored parts moved by one shared loop (no tweens).
local fxParts = {}
local FX_STYLE = {
	chips = {count = 1, speed = 14, size = 0.32, material = Enum.Material.Slate, spark = true},
	wood = {count = 1, speed = 12, size = 0.3, material = Enum.Material.Wood, leaf = true},
	splash = {count = 1.4, speed = 13, size = 0.35, material = Enum.Material.Glass, colour = "CFEFFF", up = true},
	dust = {count = 1, speed = 7, size = 0.38, material = Enum.Material.Sand, leaf = true, up = true},
	sparks = {count = 1, speed = 16, size = 0.18, material = Enum.Material.Neon, colour = "FFB347"},
	bubbles = {count = 0.8, speed = 5, size = 0.4, material = Enum.Material.Glass, colour = "9EE7D2", up = true, float = true},
	steam = {count = 0.8, speed = 4, size = 0.5, material = Enum.Material.SmoothPlastic, colour = "F2F2F2", up = true, float = true},
	sawdust = {count = 1, speed = 6, size = 0.2, material = Enum.Material.Sand, colour = "D9B77E"},
	ring = {count = 0.6, speed = 4, size = 0.25, material = Enum.Material.Neon, colour = "F9CC77", float = true},
	crumbs = {count = 0.6, speed = 5, size = 0.18, material = Enum.Material.SmoothPlastic},
	mend = {count = 1, speed = 4, size = 0.3, material = Enum.Material.Neon, colour = "8EE07F", up = true, float = true},
}
local function burst(style, position, colour, reduced)
	local spec = FX_STYLE[style]
	if not spec then return end
	local n = math.max(1, math.floor(Core.fxBudget(reduced) * spec.count))
	local camera = Workspace.CurrentCamera
	for i = 1, n do
		if #fxParts >= Core.MAX_FX_PARTS then return end
		local part = Instance.new("Part")
		part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
		part.Size = Vector3.one * spec.size * (0.7 + math.random() * 0.6)
		part.Material = spec.material
		local c = if spec.colour then Core.hex(spec.colour) else (colour or Core.hex("B0A89A"))
		if spec.spark and i % 3 == 0 then c, part.Material = Core.hex("FFD27A"), Enum.Material.Neon end
		if spec.leaf and i % 3 == 0 then c = Core.hex("6BBF59") end
		part.Color = c
		part.CFrame = CFrame.new(position) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		part.Parent = camera
		local dir = Vector3.new(math.random() - 0.5, if spec.up then 0.8 + math.random() else math.random(), math.random() - 0.5).Unit
		local speed = if reduced then 1.5 else spec.speed * (0.6 + math.random() * 0.6)
		table.insert(fxParts, {part = part, vel = dir * speed, born = os.clock(), life = 0.45 + math.random() * 0.3,
			float = spec.float, spin = math.random() * 8})
	end
end
local function stepFx(dt)
	local now = os.clock()
	for i = #fxParts, 1, -1 do
		local fx = fxParts[i]
		local age = (now - fx.born) / fx.life
		if age >= 1 or not fx.part.Parent then
			fx.part:Destroy()
			table.remove(fxParts, i)
		else
			if not fx.float then fx.vel += Vector3.new(0, -Workspace.Gravity * 0.25 * dt, 0) end
			fx.part.CFrame = (fx.part.CFrame + fx.vel * dt) * CFrame.Angles(fx.spin * dt, 0, 0)
			fx.part.Transparency = age
		end
	end
end

-- Tiny camera-safe shake via Humanoid.CameraOffset (local character only).
local shakeUntil, shakeHumanoid = 0, nil
local function shake(humanoid)
	if humanoid.CameraOffset.Magnitude > 0.3 then return end -- someone else owns the offset
	shakeHumanoid, shakeUntil = humanoid, os.clock() + 0.12
end
local function stepShake()
	if not shakeHumanoid then return end
	local left = shakeUntil - os.clock()
	if left <= 0 then
		shakeHumanoid.CameraOffset = Vector3.zero
		shakeHumanoid = nil
		return
	end
	local a = 0.12 * left / 0.12
	shakeHumanoid.CameraOffset = Vector3.new((math.random() - 0.5) * a, (math.random() - 0.5) * a, 0)
end

local function partOf(target)
	if typeof(target) ~= "Instance" then return nil end
	if target:IsA("BasePart") then return target end
	if target:IsA("Model") then return target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true) end
	if target:IsA("Attachment") then return target.Parent and target.Parent:IsA("BasePart") and target.Parent or nil end
	return target:FindFirstAncestorWhichIsA("BasePart")
end
local function resourceColour(target)
	local prompt = target and target:FindFirstChildWhichIsA("ProximityPrompt", true)
	local item = prompt and (prompt:GetAttribute("IsleItem") or prompt:GetAttribute("IsleCoopResource"))
	local def = type(item) == "string" and Data.Items[item]
	return def and Core.hex(def.color) or nil
end

local engine
local function mark(state, markName)
	local character = state.character
	local def = state.def
	local reduced = reducedMotion()
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local rigKind = Core.rigType(character)
	local hand = rigKind and character:FindFirstChild(Core.HAND[rigKind])
	local handPos = if hand then hand.Position else root.Position
	local position
	if def.fx == "splash" then
		position = (root.CFrame * CFrame.new(0, -2.5, -8)).Position
	elseif def.fx == "crumbs" or def.fx == "mend" or (def.fx == "ring" and state.target == nil) then
		position = handPos
	else
		local part = partOf(state.target)
		position = if part then Core.impactPoint(part.Position, part.Size, handPos) else (root.CFrame * CFrame.new(0, 0, -3)).Position
	end
	if def.fx and (markName ~= "bob" or not reduced) then
		burst(def.fx, position, resourceColour(partOf(state.target)), reduced)
	end
	if markName == "impact" and Core.shouldShake(reduced, def, state.isLocal) then
		local humanoid = humanoidOf(character)
		if humanoid then shake(humanoid) end
	end
end

-- Replication (local → server). Throttled locally to match the server's limit.
local sendTokens, sendStamp = 4, os.clock()
local function send(name, target, itemId)
	local now = os.clock()
	sendTokens = math.min(4, sendTokens + (now - sendStamp) * 4)
	sendStamp = now
	if sendTokens < 1 then return end
	sendTokens -= 1
	relay:FireServer(name, partOf(target), itemId)
end

local function itemFor(name)
	local def = Core.GESTURES[name]
	if def and def.skill then return bestTools[def.skill] end
	if name == "attack" or Core.STYLE_GESTURE[name] then return weaponId end
	return nil
end

engine = Core.createEngine({
	now = os.clock, alive = alive, bindRig = Core.bindRig, attachTool = attachTool, watch = watch, mark = mark,
	cycle = function(state)
		if state.isLocal then send(state.name, state.target, state.itemId) end
	end,
})

local function playLocal(name, target, opts)
	local character = player.Character
	if not Core.NAMES[name] or not alive(character) then return end
	opts = opts or {}
	local itemId = opts.itemId or itemFor(name)
	local state = engine.play(character, name, {
		target = partOf(target), hold = opts.hold, isLocal = true, color = Core.toolColor(Data, name, itemId),
		variant = math.random(1, 3), extend = opts.extend,
	})
	if state then
		state.itemId, state.prompt = itemId, opts.prompt
		send(name, target, itemId)
	end
	return state
end

-- Prompts --------------------------------------------------------------------
local function promptInfo(prompt)
	return {action = prompt:GetAttribute("IsleAction"), item = prompt:GetAttribute("IsleItem"),
		coopResource = prompt:GetAttribute("IsleCoopResource")}
end
local function promptTarget(prompt)
	return partOf(prompt.Parent)
end
local function gestureFor(prompt)
	local info = promptInfo(prompt)
	if info.action == "station" then stationCounter += 1 end
	return Core.selectGesture(info, Data, stationCounter)
end

ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, who)
	if who ~= player or not prompt.Enabled then return end
	playLocal(gestureFor(prompt), promptTarget(prompt), {hold = true, prompt = prompt})
end)
ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt, who)
	if who ~= player then return end
	local state = player.Character and engine.get(player.Character)
	if state and state.prompt == prompt then engine.release(player.Character) end
end)
ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then return end
	local state = player.Character and engine.get(player.Character)
	if state and state.prompt == prompt and not state.fadeStart then
		engine.release(player.Character) -- the current strike lands, then it ends
		return
	end
	playLocal(gestureFor(prompt), promptTarget(prompt), {prompt = prompt})
end)

-- Local API for other client scripts (combat swing, UI consume buttons).
local localApi = ReplicatedStorage:FindFirstChild("IsleGestureLocal") or Instance.new("BindableEvent")
localApi.Name = "IsleGestureLocal"
localApi.Parent = ReplicatedStorage
localApi.Event:Connect(function(name, target, itemId)
	if type(name) ~= "string" then return end
	playLocal(name, target, {itemId = if type(itemId) == "string" then itemId else nil})
end)

-- Crafting batches: the server sets CraftingGesture "<gesture>:<seq>" after
-- every action of a batch; play that gesture once per action (a new seq).
player:GetAttributeChangedSignal("CraftingGesture"):Connect(function()
	local value = player:GetAttribute("CraftingGesture")
	local name = type(value) == "string" and string.match(value, "^(%a+):%d+$")
	if name and Core.NAMES[name] then playLocal(name, nil, {}) end
end)

-- Snapshot: tool colours + eat/drink after a consume.
local updates = ReplicatedStorage:WaitForChild("IsleUpdate")
updates.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" then return end
	local depth = snapshot.depth
	if type(depth) == "table" then
		if type(depth.tools) == "table" then bestTools = depth.tools end
		if type(depth.equipment) == "table" then weaponId = depth.equipment.weapon end
	end
	local gesture, itemId = Core.consumeGesture(snapshot.message, Data)
	if gesture then playLocal(gesture, nil, {itemId = itemId}) end
end)

-- Remote characters ---------------------------------------------------------
local remoteDistance = {} -- [character] = distance when admitted
relay.OnClientEvent:Connect(function(source, name, target, itemId)
	if typeof(source) ~= "Instance" or source == player or type(name) ~= "string" or not Core.NAMES[name] then return end
	local character = source.Character
	local mine = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local theirs = character and character:FindFirstChild("HumanoidRootPart")
	if not mine or not theirs or not alive(character) then return end
	for c in pairs(remoteDistance) do
		if not engine.get(c) then remoteDistance[c] = nil end
	end
	local distance = (mine.Position - theirs.Position).Magnitude
	local admit, evict = Core.admitRemote(remoteDistance, character, distance)
	if not admit then return end
	if evict then
		engine.stop(evict)
		remoteDistance[evict] = nil
	end
	local state = engine.play(character, name, {target = partOf(target), extend = true,
		color = Core.toolColor(Data, name, if type(itemId) == "string" then itemId else nil), variant = math.random(1, 3)})
	if state then remoteDistance[character] = distance end
end)
Players.PlayerRemoving:Connect(function(who)
	local character = who.Character
	if character then
		engine.stop(character)
		remoteDistance[character] = nil
	end
end)
player.CharacterRemoving:Connect(function(character) engine.stop(character) end)

-- Agility moves: the server sets AgilityMove "<anim>:<seq>" (plus
-- AgilityMoveDuration) on any runner and moves the anchored root itself, so
-- every client watches every player's attribute: no relay is needed. The local
-- runner always animates; others follow the remote cap and range.
local function playAgility(who)
	local character = who.Character
	local name = Core.agilityGesture(who:GetAttribute("AgilityMove"))
	if not name or not alive(character) then return end
	local duration = tonumber(who:GetAttribute("AgilityMoveDuration")) or 1
	if who == player then
		engine.play(character, name, {duration = duration, isLocal = true})
		return
	end
	local mine = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local theirs = character:FindFirstChild("HumanoidRootPart")
	if not mine or not theirs then return end
	local distance = (mine.Position - theirs.Position).Magnitude
	local admit, evict = Core.admitRemote(remoteDistance, character, distance)
	if not admit then return end
	if evict then
		engine.stop(evict)
		remoteDistance[evict] = nil
	end
	if engine.play(character, name, {duration = duration}) then remoteDistance[character] = distance end
end
local function watchRunner(who)
	who:GetAttributeChangedSignal("AgilityMove"):Connect(function() playAgility(who) end)
	if who:GetAttribute("AgilityMove") then task.defer(playAgility, who) end
end
Players.PlayerAdded:Connect(watchRunner)
for _, who in ipairs(Players:GetPlayers()) do watchRunner(who) end

RunService.Stepped:Connect(function(_, dt)
	engine.step()
	if #fxParts > 0 then stepFx(dt) end
	stepShake()
end)
