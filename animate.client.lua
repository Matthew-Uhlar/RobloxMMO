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
--   2. Runtime – prompts, the IsleGesture relay, held tool parts, impact FX,
--               the held-item carry pose and auto tool switch (§26).
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
local IDENTITY -- CFrame.new(), set once CFrame is known (Core.IDENTITY)

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
-- buf (optional, from Core.poseBuffer()) is reused: the result is buf.out and
-- its per-joint arrays come from buf.pool, so the frame loop allocates no tables.
function Core.poseBuffer() return {out = {}, pool = {}} end
local function poseSlot(buf, joint)
	if not buf then return table.create(6, 0) end
	local v = buf.pool[joint]
	if not v then
		v = table.create(6, 0)
		buf.pool[joint] = v
	end
	return v
end
local function copyPose(pose, buf)
	local out = if buf then buf.out else {}
	if buf then table.clear(out) end
	for joint, v in pairs(pose) do
		local dst = poseSlot(buf, joint)
		for k = 1, 6 do dst[k] = v[k] or 0 end
		out[joint] = dst
	end
	return out
end
function Core.samplePose(keys, t, buf)
	local first = keys[1]
	if t <= first.t then return copyPose(first.pose, buf) end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b.t then
			local span = b.t - a.t
			local alpha = if span > 0 then (t - a.t) / span else 1
			alpha = (Core.ease[b.ease or "quadInOut"] or Core.ease.quadInOut)(math.clamp(alpha, 0, 1))
			local out = if buf then buf.out else {}
			if buf then table.clear(out) end
			for _, joint in ipairs(Core.JOINTS) do
				local pa, pb = a.pose[joint], b.pose[joint]
				if pa or pb then
					pa, pb = pa or ZERO, pb or ZERO
					local v = poseSlot(buf, joint)
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
	return copyPose(keys[#keys].pose, buf)
end

-- §47 crossfade: blend a sampled pose (buf.out) from a snapshot `from` by
-- alpha in [0, 1], in place (joints only in `from` get a pooled array).
Core.CROSSFADE = 0.12
function Core.blendFrom(from, pose, alpha, buf)
	for joint, fv in pairs(from) do
		local v = pose[joint]
		if not v then
			v = poseSlot(buf, joint)
			for k = 1, 6 do v[k] = 0 end
			pose[joint] = v
		end
		for k = 1, 6 do
			local x = fv[k] or 0
			v[k] = x + (v[k] - x) * alpha
		end
	end
	return pose
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
function Core.toJointSpace(r, basis, basisInv)
	return (basisInv or basis:Inverse()) * r * basis
end
IDENTITY = CFrame.new()
Core.IDENTITY = IDENTITY
-- Joints carried by the leg / root motors (QC L10).
Core.LEG_JOINTS = {rightHip = true, leftHip = true, rightKnee = true, leftKnee = true, root = true}

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
-- Weapon classes (Data.Held.ATTACK): dagger stabs, two-handed greatblade / maul
-- cleaves, glaive lunges. Blades point along the hand's -Z, so a blade lies
-- forward when the arm hangs and stands up when the arm is raised forward.
local STAB_BACK = {rightArm = {-25, 0, 14}, rightElbow = {34}, leftArm = {30, -10, -10}, leftElbow = {30}, waist = {4, -16, 0}}
local STAB_HIT = {rightArm = {46, -8, 2}, rightElbow = {0}, leftArm = {-10, 0, -12}, leftElbow = {20}, waist = {-14, 18, 0}, neck = {-6}}
local SLIT_BACK = {rightArm = {82, -55, 0}, rightElbow = {46}, waist = {0, -20, 0}}
local SLIT_HIT = {rightArm = {76, 52, 0}, rightElbow = {4}, waist = {-6, 24, 0}}
local CLEAVE_UP = {rightArm = {176, 0, 10}, rightElbow = {40}, leftArm = {170, -20, -10}, leftElbow = {46}, waist = {14, 0, 0}, neck = {8},
	rightHip = {-6}, leftHip = {10}, rightKnee = {-6}, leftKnee = {-12}}
local CLEAVE_HIT = {rightArm = {30, 0, 5}, rightElbow = {4}, leftArm = {34, -24, -5}, leftElbow = {10}, waist = {-28, 0, 0}, neck = {-12},
	root = {0, 0, 0, 0, -0.45, 0}, rightHip = {38}, leftHip = {-8}, rightKnee = {-46}, leftKnee = {-20}}
local SWEEP_BACK = {rightArm = {84, -82, 0}, rightElbow = {22}, leftArm = {80, -92, 0}, leftElbow = {30}, waist = {0, -42, 0}, neck = {0, 12, 0}}
local SWEEP_HIT = {rightArm = {80, 72, 0}, rightElbow = {6}, leftArm = {74, 56, 0}, leftElbow = {14}, waist = {-8, 42, 0}, neck = {0, -10, 0}}
local LUNGE_BACK = {rightArm = {-18, 0, 10}, rightElbow = {20}, leftArm = {38, -30, -10}, leftElbow = {50}, waist = {10, -10, 0},
	rightHip = {-12}, leftHip = {14}, rightKnee = {-10}, leftKnee = {-24}}
local LUNGE_HIT = {rightArm = {32, 0, 4}, rightElbow = {0}, leftArm = {48, -20, -6}, leftElbow = {8}, waist = {-22, 0, 0}, neck = {-8},
	root = {0, 0, 0, 0, -0.35, -0.6}, rightHip = {52}, leftHip = {-22}, rightKnee = {-48}, leftKnee = {-6}}
-- Hoe: a two-handed chop at the soil from the harvest crouch.
local HOE_UP = merge(CROUCH, {rightArm = {140, 0, 10}, rightElbow = {30}, leftArm = {122, -20, -8}, leftElbow = {40}, waist = {-10, 0, 0}})
local HOE_HIT = merge(CROUCH, {rightArm = {48, 0, 5}, rightElbow = {6}, leftArm = {50, -20, -5}, leftElbow = {10}, waist = {-40, 0, 0}})
-- Hunter: set a trap (crouch, hands to the ground) and swing a net.
local NET_BACK = {rightArm = {150, -40, 10}, rightElbow = {30}, leftArm = {40, -20, -10}, leftElbow = {40}, waist = {4, -26, 0}, neck = {0, 10, 0}}
local NET_SWEEP = {rightArm = {96, 46, 0}, rightElbow = {8}, leftArm = {30, 10, -10}, leftElbow = {30}, waist = {-10, 24, 0}}
-- Beaconry (§37): crouch over the kindling, the left hand steadies the tinder
-- low, the right hand (striker) draws back and rakes down across it.
local KINDLE_READY = merge(CROUCH, {rightArm = {72, 8, 12}, rightElbow = {58}, leftArm = {58, -22, -12}, leftElbow = {34}, waist = {-34, 0, 0}})
local KINDLE_UP = merge(CROUCH, {rightArm = {112, 18, 16}, rightElbow = {88}, leftArm = {58, -22, -12}, leftElbow = {34}, waist = {-28, 6, 0}})
local KINDLE_STRIKE = merge(CROUCH, {rightArm = {46, -14, 6}, rightElbow = {18}, leftArm = {54, -18, -10}, leftElbow = {30}, waist = {-40, -4, 0}, neck = {20}})

local P = {} -- §47 poses (a table: the chunk is near Luau's 200-local limit)
-- §47 Animation depth: anticipation → strike → follow-through → recovery on
-- every swing, stances per node size, weapon-class combos and the interaction
-- library. Signs: +rx raises an arm forward / tips the torso back (waist -rx =
-- bend forward), elbows flex positive, knees flex negative, neck +rx looks up.
-- Gathering (the loop is the server's swing cadence, Core.STRIKE).
P.MINE_COIL = {rightArm = {42, 0, 10}, rightElbow = {52}, leftArm = {40, -25, -10}, leftElbow = {55}, waist = {-10, 18, 0}, neck = {-4}}
P.MINE_FOLLOW = {rightArm = {22, 0, 4}, rightElbow = {12}, leftArm = {24, -15, -4}, leftElbow = {16}, waist = {-28, 4, 0}, neck = {-12}}
-- Low ore (a rock at the feet): the swing comes from a crouch and lands low.
P.MINE_LOW_READY = merge(CROUCH, {rightArm = {40, 0, 10}, rightElbow = {30}, leftArm = {38, -22, -10}, leftElbow = {34}, waist = {-26, 12, 0}})
P.MINE_LOW_COIL = merge(CROUCH, {rightArm = {30, 0, 10}, rightElbow = {44}, leftArm = {30, -22, -10}, leftElbow = {46}, waist = {-30, 16, 0}})
P.MINE_LOW_UP = merge(CROUCH, {rightArm = {138, 0, 12}, rightElbow = {44}, leftArm = {128, -15, -8}, leftElbow = {40}, waist = {-12, 10, 0}, neck = {-6}})
P.MINE_LOW_HIT = merge(CROUCH, {rightArm = {12, 0, 4}, rightElbow = {4}, rightWrist = {-30}, leftArm = {14, -15, -4}, leftElbow = {8},
	waist = {-42, 4, 0}, neck = {-16}})
P.MINE_LOW_FOLLOW = merge(CROUCH, {rightArm = {4, 0, 4}, rightElbow = {10}, rightWrist = {-36}, leftArm = {6, -15, -4}, leftElbow = {14},
	waist = {-46, 2, 0}, neck = {-18}})
-- High vein (above the shoulders): weight back, then the pick bites in at head height.
P.MINE_HIGH_READY = {rightArm = {95, 0, 10}, rightElbow = {30}, leftArm = {88, -22, -10}, leftElbow = {36}, waist = {4, 12, 0}, neck = {14}}
P.MINE_HIGH_COIL = {rightArm = {86, 0, 10}, rightElbow = {44}, leftArm = {80, -22, -10}, leftElbow = {48}, waist = {-2, 16, 0}, neck = {12}}
P.MINE_HIGH_UP = {rightArm = {176, 0, 14}, rightElbow = {58}, leftArm = {168, -15, -8}, leftElbow = {52}, waist = {16, 10, 0}, neck = {18}}
P.MINE_HIGH_HIT = {rightArm = {118, 0, 6}, rightElbow = {0}, rightWrist = {-22}, leftArm = {112, -15, -5}, leftElbow = {6}, waist = {-6, 4, 0}, neck = {16}}
P.MINE_HIGH_FOLLOW = {rightArm = {106, 0, 6}, rightElbow = {8}, rightWrist = {-28}, leftArm = {100, -15, -5}, leftElbow = {12}, waist = {-10, 2, 0}, neck = {12}}
P.CHOP_COIL = {rightArm = {72, -24, 0}, rightElbow = {30}, leftArm = {62, -45, 0}, leftElbow = {42}, waist = {-4, -10, 0}}
P.CHOP_FOLLOW = {rightArm = {74, 52, 0}, rightElbow = {10}, leftArm = {64, 34, 0}, leftElbow = {20}, waist = {-8, 30, 0}, neck = {0, -8, 0}}
-- Low trunk (saplings, stumps): knees bent, the axe swings flatter and lower.
P.LOW_STANCE = {root = {0, 0, 0, 0, -0.45, 0}, rightHip = {32}, leftHip = {22}, rightKnee = {-44}, leftKnee = {-36}}
P.CHOP_LOW_READY = merge(P.LOW_STANCE, {rightArm = {48, -10, 0}, rightElbow = {20}, leftArm = {40, -35, 0}, leftElbow = {35}, waist = {-18, 0, 0}})
P.CHOP_LOW_COIL = merge(P.LOW_STANCE, {rightArm = {44, -28, 0}, rightElbow = {30}, leftArm = {38, -48, 0}, leftElbow = {42}, waist = {-20, -10, 0}})
P.CHOP_LOW_BACK = merge(P.LOW_STANCE, {rightArm = {60, -78, 0}, rightElbow = {35}, leftArm = {52, -72, 0}, leftElbow = {50}, waist = {-14, -30, 0}})
P.CHOP_LOW_HIT = merge(P.LOW_STANCE, {rightArm = {42, 32, 0}, rightElbow = {4}, leftArm = {38, 16, 0}, leftElbow = {14}, waist = {-24, 22, 0}, neck = {-8}})
P.CHOP_LOW_FOLLOW = merge(P.LOW_STANCE, {rightArm = {38, 54, 0}, rightElbow = {10}, leftArm = {34, 34, 0}, leftElbow = {20}, waist = {-26, 30, 0}, neck = {-10}})
-- Crops: a sickle sweep from the crouch; the free hand gathers the cut stalks.
P.SICKLE_READY = merge(CROUCH, {rightArm = {48, -20, 8}, rightElbow = {22}, leftArm = {52, -10, -8}, leftElbow = {30}})
P.SICKLE_COIL = merge(CROUCH, {rightArm = {44, -36, 10}, rightElbow = {30}, leftArm = {56, 0, -8}, leftElbow = {24}, waist = {-32, -8, 0}})
P.SICKLE_WIND = merge(CROUCH, {rightArm = {52, -72, 12}, rightElbow = {26}, leftArm = {60, 12, -6}, leftElbow = {18}, waist = {-28, -24, 0}, neck = {0, -10, 0}})
P.SICKLE_HIT = merge(CROUCH, {rightArm = {40, 34, 6}, rightElbow = {6}, rightWrist = {-20}, leftArm = {46, 20, -6}, leftElbow = {12},
	waist = {-38, 18, 0}, neck = {-10, 8, 0}})
P.SICKLE_FOLLOW = merge(CROUCH, {rightArm = {38, 52, 6}, rightElbow = {12}, rightWrist = {-24}, leftArm = {30, 30, -10}, leftElbow = {70},
	waist = {-34, 24, 0}, neck = {-12, 10, 0}})
-- Tall plants (a bush at waist height or above): the same sweep standing.
P.SWEEP_HI_READY = {rightArm = {60, -20, 8}, rightElbow = {24}, leftArm = {52, -10, -8}, leftElbow = {34}, waist = {-6, 0, 0}}
P.SWEEP_HI_COIL = {rightArm = {56, -36, 10}, rightElbow = {30}, leftArm = {56, 0, -8}, leftElbow = {28}, waist = {-8, -8, 0}}
P.SWEEP_HI_WIND = {rightArm = {68, -76, 12}, rightElbow = {26}, leftArm = {58, 10, -6}, leftElbow = {20}, waist = {-4, -26, 0}}
P.SWEEP_HI_HIT = {rightArm = {62, 36, 6}, rightElbow = {6}, leftArm = {54, 20, -6}, leftElbow = {14}, waist = {-10, 20, 0}}
P.SWEEP_HI_FOLLOW = {rightArm = {58, 54, 6}, rightElbow = {12}, leftArm = {40, 30, -10}, leftElbow = {70}, waist = {-10, 26, 0}}
-- Fishing: load the rod back, whip the cast, follow through low; hook-set and crank on the reel.
P.FISH_FOLLOW = {rightArm = {60, 0, 4}, rightElbow = {2}, leftArm = {28, -15, -8}, leftElbow = {20}, waist = {-16, 0, 0}, neck = {-6}}
P.FISH_SET = {rightArm = {118, 0, 8}, rightElbow = {40}, leftArm = {64, -28, -6}, leftElbow = {60}, waist = {10, 0, 0}, neck = {6}}
P.FISH_CRANK = merge(FISH_REEL, {leftArm = {74, -24, -2}, leftElbow = {84}, rightWrist = {10}})
P.FISH_TUG = merge(FISH_HOLD, {rightArm = {52, 0, 6}, rightElbow = {30}, waist = {-8, 0, 0}, neck = {-6}})

-- Weapon combos. Sword: forehand cut, backhand cut, overhead finisher.
P.SW1_COIL = {rightArm = {88, -72, 0}, rightElbow = {38}, leftArm = {30, 20, -10}, leftElbow = {40}, waist = {0, -26, 0}, neck = {0, 10, 0}}
P.SW1_HIT = {rightArm = {86, 52, 0}, rightElbow = {6}, leftArm = {20, -10, -14}, leftElbow = {30}, waist = {-6, 24, 0}, neck = {0, -6, 0}}
P.SW1_FOLLOW = {rightArm = {70, 80, 0}, rightElbow = {14}, leftArm = {18, -14, -16}, leftElbow = {28}, waist = {-8, 32, 0}, neck = {0, -10, 0}}
P.SW2_COIL = {rightArm = {94, 62, 0}, rightElbow = {72}, leftArm = {24, -10, -12}, leftElbow = {36}, waist = {0, 24, 0}}
P.SW2_HIT = {rightArm = {86, -58, 0}, rightElbow = {6}, leftArm = {28, 16, -10}, leftElbow = {34}, waist = {-6, -24, 0}}
P.SW2_FOLLOW = {rightArm = {72, -82, 0}, rightElbow = {14}, leftArm = {30, 20, -10}, leftElbow = {36}, waist = {-8, -32, 0}}
P.SW3_DIP = {rightArm = {50, 0, 8}, rightElbow = {60}, leftArm = {40, -10, -12}, leftElbow = {50}, waist = {-8, 0, 0}}
P.SW3_COIL = {rightArm = {172, 0, 12}, rightElbow = {52}, leftArm = {120, -10, -14}, leftElbow = {40}, waist = {12, 0, 0}, neck = {8}}
P.SW3_HIT = {rightArm = {42, 0, 4}, rightElbow = {4}, leftArm = {30, -10, -10}, leftElbow = {20}, waist = {-20, 0, 0}, neck = {-10}}
P.SW3_FOLLOW = {rightArm = {18, 0, 4}, rightElbow = {10}, leftArm = {16, -10, -12}, leftElbow = {24}, waist = {-28, 0, 0}, neck = {-14}}
-- Dagger: two quick jabs and a backhand slit.
P.STAB_FOLLOW = {rightArm = {52, -10, 2}, rightElbow = {0}, leftArm = {-12, 0, -12}, leftElbow = {20}, waist = {-16, 22, 0}, neck = {-6}}
P.STAB2_BACK = {rightArm = {-10, 10, 20}, rightElbow = {60}, leftArm = {24, -6, -10}, leftElbow = {30}, waist = {4, -10, 0}}
P.STAB2_HIT = {rightArm = {64, 8, 0}, rightElbow = {4}, leftArm = {-6, 0, -12}, leftElbow = {20}, waist = {-12, 14, 0}, neck = {-4}}
P.STAB2_FOLLOW = merge(P.STAB2_HIT, {rightArm = {70, 12, 0}, waist = {-14, 18, 0}})
P.SLIT_FOLLOW = {rightArm = {68, 74, 0}, rightElbow = {10}, waist = {-8, 30, 0}}
-- Greatblade / maul / axe: heavy. A dip before the wind-up, a long follow-through.
P.CLEAVE_DIP = {rightArm = {20, 0, 10}, rightElbow = {70}, leftArm = {20, -20, -10}, leftElbow = {74}, waist = {-10, 0, 0}, neck = {-4}}
P.CLEAVE_FOLLOW = merge(CLEAVE_HIT, {rightArm = {14, 0, 5}, leftArm = {18, -24, -5}, waist = {-34, 0, 0}, neck = {-14}})
P.SWEEP_COIL = {rightArm = {60, -40, 0}, rightElbow = {40}, leftArm = {56, -50, 0}, leftElbow = {50}, waist = {-8, -16, 0}}
P.SWEEP_FOLLOW = {rightArm = {70, 92, 0}, rightElbow = {12}, leftArm = {62, 70, 0}, leftElbow = {20}, waist = {-10, 48, 0}, neck = {0, -14, 0}}
-- Glaive: a coiled lunge.
P.LUNGE_COIL = {rightArm = {10, 0, 10}, rightElbow = {40}, leftArm = {30, -30, -10}, leftElbow = {60}, waist = {4, -6, 0}}
P.LUNGE_FOLLOW = merge(LUNGE_HIT, {rightArm = {28, 0, 4}, waist = {-26, 0, 0}})
-- Bow: hold at anchor a beat, the string hand flies back on the loose.
P.BOW_ANCHOR = merge(BOW_DRAW, {rightArm = {93, 55, 0}, rightElbow = {132}, neck = {-5, 21, 0}})
P.BOW_FOLLOW = {leftArm = {86, 12, 0}, leftElbow = {6}, rightArm = {80, 8, 46}, rightElbow = {24}, waist = {0, -20, 0}, neck = {-2, 16, 0}}
-- Staff: gather the charge at the chest, raise, thrust, settle.
P.STAFF_GATHER = {rightArm = {50, 0, 12}, rightElbow = {80}, leftArm = {46, -20, -10}, leftElbow = {86}, waist = {-6, 0, 0}, neck = {-6}}
P.STAFF_FOLLOW = merge(STAFF_THRUST, {rightArm = {92, 0, 6}, waist = {-16, 0, 0}})
P.WAND_COIL = {rightArm = {40, 10, 8}, rightElbow = {70}, rightWrist = {-20}}
P.WAND_FOLLOW = {rightArm = {78, 16, 4}, rightElbow = {4}, rightWrist = {45}, waist = {-8, 0, 0}}
-- Eat / drink.
P.EAT_CHEW = merge(EAT_UP, {neck = {-2}})
P.DRINK_DEEP = {rightArm = {92, 25, 0}, rightElbow = {126}, neck = {32}}
P.DRINK_WIPE = {rightArm = {60, 40, 0}, rightElbow = {120}, neck = {-4}}

-- Interactions.
P.WAVE_UP = {rightArm = {100, 0, 50}, rightElbow = {70}, neck = {4}}
P.WAVE_A = {rightArm = {104, 0, 60}, rightElbow = {58}, neck = {4, 6, 0}}
P.WAVE_B = {rightArm = {100, 0, 42}, rightElbow = {82}, neck = {4, -4, 0}}
P.TALK_OPEN = {rightArm = {40, 22, 0}, rightElbow = {82}, leftArm = {30, -18, 0}, leftElbow = {70}, neck = {-2}}
P.NOD_DOWN = merge(P.TALK_OPEN, {neck = {-14}})
P.NOD_UP = merge(P.TALK_OPEN, {neck = {4}})
P.KNEEL = {root = {0, 0, 0, 0, -1.3, 0}, leftHip = {84}, leftKnee = {-90}, rightHip = {-4}, rightKnee = {-112}}
P.BEND = {root = {0, 0, 0, 0, -0.5, 0}, rightHip = {40}, leftHip = {34}, rightKnee = {-52}, leftKnee = {-46}}
P.OPEN_GRIP = merge(P.BEND, {rightArm = {50, -10, 6}, rightElbow = {30}, leftArm = {50, 10, -6}, leftElbow = {30}, waist = {-30, 0, 0}, neck = {-10}})
P.OPEN_DIP = merge(P.OPEN_GRIP, {waist = {-36, 0, 0}, rightElbow = {36}, leftElbow = {36}})
P.OPEN_LIFT = merge(P.BEND, {rightArm = {112, -10, 8}, rightElbow = {20}, leftArm = {112, 10, -8}, leftElbow = {20}, waist = {-8, 0, 0}, neck = {6}})
P.OPEN_LOOK = merge(P.BEND, {rightArm = {40, -10, 8}, rightElbow = {40}, leftArm = {40, 10, -8}, leftElbow = {40}, waist = {-18, 0, 0}, neck = {-14}})
P.POUR_LIFT = {rightArm = {74, 20, 0}, rightElbow = {72}, leftArm = {52, -24, -6}, leftElbow = {64}, waist = {-6, 0, 0}, neck = {-8}}
P.POUR_TIP = merge(P.POUR_LIFT, {rightArm = {80, 14, 0}, rightElbow = {54}, rightWrist = {0, 0, 70}, neck = {-14}})
P.WEAVE_A = {rightArm = {70, 30, 0}, rightElbow = {40}, leftArm = {62, -10, 0}, leftElbow = {60}, waist = {-8, 8, 0}, neck = {-10, 6, 0}}
P.WEAVE_B = {rightArm = {62, 10, 0}, rightElbow = {60}, leftArm = {70, -30, 0}, leftElbow = {40}, waist = {-8, -8, 0}, neck = {-10, -6, 0}}
P.WEAVE_BEAT = merge(P.WEAVE_A, {rightArm = {48, 0, 0}, rightElbow = {20}, leftArm = {48, 0, 0}, leftElbow = {20}, waist = {-14, 0, 0}})
P.BLOW_HOLD = {rightArm = {80, 30, 0}, rightElbow = {110}, leftArm = {75, -20, 0}, leftElbow = {100}, neck = {-4}}
P.BLOW_INHALE = merge(P.BLOW_HOLD, {waist = {6, 0, 0}, neck = {2}})
P.BLOW_PUFF = merge(P.BLOW_HOLD, {waist = {-6, 0, 0}, neck = {-8}, rightWrist = {0, 0, 40}})
P.SIFT_A = {rightArm = {48, 10, 10}, rightElbow = {50}, leftArm = {48, -10, -10}, leftElbow = {50}, waist = {-12, 0, -4}, neck = {-14}}
P.SIFT_B = merge(P.SIFT_A, {rightArm = {48, 22, 10}, leftArm = {48, 2, -10}, waist = {-12, 0, 4}})
P.POUCH = {rightArm = {-18, 0, 20}, rightElbow = {64}, waist = {-4, 0, 0}, neck = {-12}}
P.HAND_OVER = {rightArm = {72, -6, 0}, rightElbow = {16}, waist = {-10, 0, 0}, neck = {-6}}
P.HAND_SET = merge(P.HAND_OVER, {rightArm = {62, -6, 0}, rightElbow = {10}, waist = {-14, 0, 0}})
P.DIG_A = merge(CROUCH, {rightArm = {42, 0, 8}, rightElbow = {20}, rightWrist = {-30}, leftArm = {30, -10, -8}, leftElbow = {40}})
P.DIG_B = merge(CROUCH, {rightArm = {22, 0, 8}, rightElbow = {8}, rightWrist = {-50}, leftArm = {30, -10, -8}, leftElbow = {40}, waist = {-36, 0, 0}})
P.SEED = merge(CROUCH, {rightArm = {36, 10, 0}, rightElbow = {30}, leftArm = {44, -10, 0}, leftElbow = {60}, neck = {-10}})
P.PAT = merge(CROUCH, {rightArm = {24, 8, 4}, rightElbow = {4}, leftArm = {24, -8, -4}, leftElbow = {4}, waist = {-40, 0, 0}, neck = {-12}})
P.WATER_HOLD = {rightArm = {58, 6, 4}, rightElbow = {24}, leftArm = {20, -10, -8}, leftElbow = {30}, waist = {-6, 0, 0}, neck = {-12}}
P.WATER_TIP = merge(P.WATER_HOLD, {rightWrist = {-46}, rightArm = {62, 6, 4}, waist = {-10, 0, 0}})
P.WATER_SWAY = merge(P.WATER_TIP, {rightArm = {62, 18, 4}, waist = {-10, 6, 0}})
P.TEND_A = merge(CROUCH, {rightArm = {36, 6, 6}, rightElbow = {18}, leftArm = {44, -6, -6}, leftElbow = {30}})
P.TEND_B = merge(CROUCH, {rightArm = {46, 6, 6}, rightElbow = {30}, leftArm = {32, -6, -6}, leftElbow = {16}, waist = {-36, 0, 0}})
P.PRAY = merge(P.KNEEL, {rightArm = {42, 34, 0}, rightElbow = {100}, leftArm = {42, -34, 0}, leftElbow = {100}, waist = {-10, 0, 0}, neck = {-24}})
P.PRAY_DEEP = merge(P.PRAY, {waist = {-18, 0, 0}, neck = {-30}})
P.OFFER_UP = merge(P.KNEEL, {rightArm = {128, 14, 0}, rightElbow = {30}, leftArm = {128, -14, 0}, leftElbow = {30}, waist = {6, 0, 0}, neck = {16}})
P.OFFER_DOWN = merge(P.KNEEL, {rightArm = {48, 14, 0}, rightElbow = {20}, leftArm = {48, -14, 0}, leftElbow = {20}, waist = {-20, 0, 0}, neck = {-14}})
P.STOOP = merge(P.BEND, {rightArm = {36, 0, 6}, rightElbow = {6}, leftArm = {10, 0, -14}, leftElbow = {30}, waist = {-50, 0, 0}, neck = {-12}})
P.STOOP_GRAB = merge(P.STOOP, {rightArm = {30, 0, 4}, rightElbow = {16}, waist = {-54, 0, 0}})
P.STOW = {rightArm = {48, 30, 0}, rightElbow = {108}, leftArm = {10, 0, -10}, leftElbow = {20}, waist = {-4, 0, 0}, neck = {-8}}
P.ATTUNE_REACH = {rightArm = {118, 8, 14}, rightElbow = {16}, rightWrist = {-30}, leftArm = {24, 0, -20}, leftElbow = {20}, waist = {4, 0, 0}, neck = {10}}
P.ATTUNE_PUSH = merge(P.ATTUNE_REACH, {rightArm = {126, 8, 14}, rightElbow = {4}, waist = {6, 0, 0}, neck = {14}})
-- §49 Runebinding: cup the shards at the chest, then thrust both palms at the altar.
P.BIND_GATHER = {rightArm = {44, 18, 0}, rightElbow = {72}, leftArm = {44, -18, 0}, leftElbow = {72}, waist = {-10, 0, 0}, neck = {-8}}
P.BIND_RISE = {rightArm = {70, 14, 0}, rightElbow = {50}, leftArm = {70, -14, 0}, leftElbow = {50}, waist = {-4, 0, 0}, neck = {2}}
P.BIND_RELEASE = {rightArm = {112, 10, 0}, rightElbow = {8}, leftArm = {112, -10, 0}, leftElbow = {8}, waist = {6, 0, 0}, neck = {12}}
-- §51 Skysailing: grab the rail and step up (board); both hands on the wheel,
-- a turn each way (helm); wind up and throw the grapple, then haul hand over
-- hand (grapple); heave a sheet line in to trim the sails (haul).
P.BOARD_REACH = {rightArm = {120, 10, 0}, rightElbow = {30}, leftArm = {96, -10, 0}, leftElbow = {44}, waist = {-8, 0, 0}, neck = {14}, rightHip = {40}, rightKnee = {-50}}
P.BOARD_STEP = {rightArm = {100, 8, 0}, rightElbow = {70}, leftArm = {80, -8, 0}, leftElbow = {80}, waist = {-14, 0, 0}, neck = {6}, rightHip = {62}, rightKnee = {-70}, leftHip = {-6}}
P.BOARD_UP = {rightArm = {60, 6, 0}, rightElbow = {40}, leftArm = {40, -6, 0}, leftElbow = {50}, waist = {-4, 0, 0}, neck = {4}, rightHip = {18}, rightKnee = {-20}}
P.HELM_GRIP = {rightArm = {70, 18, 0}, rightElbow = {58}, leftArm = {70, -18, 0}, leftElbow = {58}, waist = {-4, 0, 0}, neck = {-4}}
P.HELM_LEFT = merge(P.HELM_GRIP, {rightArm = {86, 10, 0}, rightElbow = {44}, leftArm = {56, -24, 0}, leftElbow = {72}, waist = {-4, 12, 0}, neck = {-4, 10, 0}})
P.HELM_RIGHT = merge(P.HELM_GRIP, {rightArm = {56, 24, 0}, rightElbow = {72}, leftArm = {86, -10, 0}, leftElbow = {44}, waist = {-4, -12, 0}, neck = {-4, -10, 0}})
P.GRAPPLE_WIND = {rightArm = {150, 30, 20}, rightElbow = {60}, rightWrist = {-30}, leftArm = {40, -20, 0}, leftElbow = {30}, waist = {6, 24, 0}, neck = {10, -10, 0}}
P.GRAPPLE_THROW = {rightArm = {96, -10, 0}, rightElbow = {6}, rightWrist = {20}, leftArm = {30, -20, 0}, leftElbow = {40}, waist = {-10, -16, 0}, neck = {0, 8, 0}}
P.HAUL_HIGH = {rightArm = {110, 8, 0}, rightElbow = {40}, leftArm = {80, -8, 0}, leftElbow = {50}, waist = {-6, 0, 0}, neck = {8}}
P.HAUL_LOW = {rightArm = {40, 8, 0}, rightElbow = {90}, leftArm = {70, -8, 0}, leftElbow = {60}, waist = {-18, 0, 0}, neck = {-6}}
P.READ = {rightArm = {44, 16, 0}, rightElbow = {96}, leftArm = {44, -16, 0}, leftElbow = {96}, waist = {-6, 0, 0}, neck = {-20}}
P.READ_TURN = merge(P.READ, {rightArm = {52, 36, 0}, rightElbow = {70}, neck = {-18, 6, 0}})
P.SHADE = {rightArm = {150, 40, 0}, rightElbow = {132}, waist = {2, 0, 0}, neck = {6, 30, 0}}
P.SHADE_R = merge(P.SHADE, {neck = {6, -30, 0}, waist = {2, -10, 0}})
P.PILFER_LEAN = {rightArm = {20, -10, 10}, rightElbow = {50}, waist = {-16, 6, 0}, neck = {-6, 10, 0}}
P.PILFER_GRAB = {rightArm = {60, -20, 0}, rightElbow = {10}, waist = {-20, -6, 0}, neck = {-6, 6, 0}}
-- Idle fidgets with a held item (observed: every client plays them from what it sees).
P.TWIRL = {rightArm = {50, 20, 10}, rightElbow = {70}}
P.HEAVY_REST = {rightArm = {34, 0, 12}, rightElbow = {112}, waist = {0, 0, 4}, neck = {0, 20, 0}}
P.TAP_A = {rightArm = {50, 20, 0}, rightElbow = {80}, leftArm = {45, -30, 0}, leftElbow = {70}, neck = {-12}}
P.TAP_B = merge(P.TAP_A, {rightArm = {44, 20, 0}, rightElbow = {92}})
P.STRING_CHECK = {leftArm = {60, 20, 0}, leftElbow = {20}, rightArm = {65, 35, 0}, rightElbow = {100}, neck = {-6, 14, 0}}
P.STAFF_TAP_UP = {rightArm = {26, 0, 6}, rightElbow = {60}}
P.STAFF_TAP = {rightArm = {12, 0, 6}, rightElbow = {72}, neck = {-6}}
P.LINE_CHECK = {rightArm = {40, 0, 6}, rightElbow = {70}, leftArm = {30, -20, -6}, leftElbow = {80}, neck = {-16}}
-- Death: knees buckle, then a slump forward (held; the body is removed on respawn).
-- QC M4: no root offset, so the physically falling corpse is never pushed into the floor (no owner-side jitter).
P.DEATH_BUCKLE = {rightArm = {-10, 0, 20}, rightElbow = {20}, leftArm = {-10, 0, -20}, leftElbow = {20}, waist = {-20, 0, 0}, neck = {-20},
	rightHip = {50}, leftHip = {44}, rightKnee = {-60}, leftKnee = {-56}}
P.DEATH_FALL = {rightArm = {-15, 0, 25}, rightElbow = {10}, leftArm = {-15, 0, -25}, leftElbow = {12}, waist = {-35, 0, 6}, neck = {-30, 0, 10},
	rightHip = {80}, leftHip = {76}, rightKnee = {-100}, leftKnee = {-104}}

-- Gathering strike timing (Data.Strike): the loop is exactly the server's
-- swing cadence, and intro + the loop's impact key is the client's strike
-- delay, so every strike lands on the frame the strike is sent.
Core.STRIKE_INTRO = 0.06
Core.STRIKE_GRACE, Core.STRIKE_GRACE_REMOTE = 0.15, 0.3
Core.STRIKE = {mine = {skill = "Mining", swing = 0.7, impact = 0.42}, chop = {skill = "Woodcutting", swing = 0.7, impact = 0.40},
	harvest = {skill = "Farming", swing = 0.6, impact = 0.36}}
-- Tier flourish after the last strike (Core.flourishLevel ≥ 1): a wrist twirl.
local function flourishOutro(ready)
	local up = merge(ready, {rightArm = {78, 10, 14}, rightElbow = {70}, rightWrist = {0, 0, 0}})
	return {key(0, ready), key(0.14, up, "quadOut"), key(0.28, merge(up, {rightWrist = {0, 0, 80}}), "sineInOut"),
		key(0.42, merge(up, {rightWrist = {0, 0, -12}}), "backOut", "flourish"), key(0.62, REST, "quadInOut")}
end
local function strikeGesture(base, fields, ready, coil, wind, hit, follow)
	local T = Core.STRIKE[base]
	local i = T.impact - Core.STRIKE_INTRO
	fields.strike = base
	fields.intro = {key(0, REST), key(Core.STRIKE_INTRO, ready, "quadOut")}
	fields.loop = {key(0, ready), key(i * 0.25, coil, "quadOut"), key(i * 0.72, wind, "quadOut"), key(i, hit, "quadIn", "impact"),
		key(i + 0.1, follow, "quadOut"), key(T.swing, ready, "sineInOut")}
	fields.outro = {key(0, ready), key(0.22, REST, "quadInOut")}
	fields.outroFlourish = flourishOutro(ready)
	-- QC M3: after the last strike the ready pose holds briefly (longer for
	-- observers: relay jitter) so a strike that is a little late re-phases the
	-- loop instead of dropping into the recovery.
	fields.ready = ready
	fields.graceLocal = {key(0, ready), key(Core.STRIKE_GRACE, ready)}
	fields.graceRemote = {key(0, ready), key(Core.STRIKE_GRACE_REMOTE, ready)}
	return fields
end
-- A stance variant of a relayed gesture: chosen on every client from the
-- target node's size and height (Core.stanceFor), never relayed itself.
local function stance(base, fields)
	fields.base, fields.derived = base, true
	return fields
end

-- Gesture table. intro/loop/outro are keyframe lists; the loop repeats while
-- the prompt is held (and at least minCycles times). marks fire impact FX.
-- tool = held model kind; skill = which snapshot tool colours it.
-- §47 fields: strike (gathering cadence), base/derived (stance variants),
-- combo (weapon chains: window seconds, hitstops per step), stopOnMove (legs
-- kneel / crouch: walking away fades it out), rod (rod bend), observed (every
-- client derives it from what it sees: never relayed), dead (plays on a corpse).
Core.GESTURES = {
	mine = strikeGesture("mine", {tool = "Pickaxe", skill = "Mining", fx = "chips", shake = true}, MINE_READY, P.MINE_COIL, MINE_UP, MINE_HIT, P.MINE_FOLLOW),
	mine_low = strikeGesture("mine", stance("mine", {tool = "Pickaxe", skill = "Mining", fx = "chips", shake = true}),
		P.MINE_LOW_READY, P.MINE_LOW_COIL, P.MINE_LOW_UP, P.MINE_LOW_HIT, P.MINE_LOW_FOLLOW),
	mine_high = strikeGesture("mine", stance("mine", {tool = "Pickaxe", skill = "Mining", fx = "chips", shake = true}),
		P.MINE_HIGH_READY, P.MINE_HIGH_COIL, P.MINE_HIGH_UP, P.MINE_HIGH_HIT, P.MINE_HIGH_FOLLOW),
	chop = strikeGesture("chop", {tool = "Hatchet", skill = "Woodcutting", fx = "wood", shake = true}, CHOP_READY, P.CHOP_COIL, CHOP_BACK, CHOP_HIT, P.CHOP_FOLLOW),
	chop_low = strikeGesture("chop", stance("chop", {tool = "Hatchet", skill = "Woodcutting", fx = "wood", shake = true}),
		P.CHOP_LOW_READY, P.CHOP_LOW_COIL, P.CHOP_LOW_BACK, P.CHOP_LOW_HIT, P.CHOP_LOW_FOLLOW),
	harvest = strikeGesture("harvest", {tool = "Hoe", skill = "Farming", fx = "dust"}, P.SICKLE_READY, P.SICKLE_COIL, P.SICKLE_WIND, P.SICKLE_HIT, P.SICKLE_FOLLOW),
	harvest_high = strikeGesture("harvest", stance("harvest", {tool = "Hoe", skill = "Farming", fx = "dust"}),
		P.SWEEP_HI_READY, P.SWEEP_HI_COIL, P.SWEEP_HI_WIND, P.SWEEP_HI_HIT, P.SWEEP_HI_FOLLOW),
	fish = {tool = "Rod", skill = "Fishing", fx = "splash", minCycles = 0, rod = true, remoteHold = 30,
		intro = {key(0, REST), key(0.14, FISH_HOLD, "quadOut"), key(0.34, FISH_BACK, "quadOut"), key(0.46, FISH_CAST, "quadIn", "cast"),
			key(0.58, P.FISH_FOLLOW, "quadOut"), key(0.78, FISH_HOLD, "sineInOut")},
		loop = {key(0, FISH_HOLD), key(0.45, FISH_DIP, "sineInOut", "bob"), key(0.9, FISH_HOLD, "sineInOut")},
		outro = {key(0, FISH_HOLD), key(0.12, P.FISH_SET, "backOut", "reel"), key(0.3, FISH_REEL, "sineInOut"), key(0.44, P.FISH_CRANK, "sineInOut"),
			key(0.58, FISH_REEL, "sineInOut"), key(0.8, REST, "quadInOut")}},
	-- Reel / bite as one-shots (a relay that arrives with no cast on screen).
	reel = {tool = "Rod", skill = "Fishing", fx = "splash", rod = true,
		loop = {key(0, REST), key(0.12, FISH_HOLD, "quadOut"), key(0.24, P.FISH_SET, "backOut", "reel"), key(0.42, FISH_REEL, "sineInOut"),
			key(0.56, P.FISH_CRANK, "sineInOut"), key(0.86, REST, "quadInOut")}},
	bite = {tool = "Rod", skill = "Fishing", fx = "splash", rod = true,
		loop = {key(0, REST), key(0.12, FISH_HOLD, "quadOut"), key(0.2, P.FISH_TUG, "quadIn", "bob"), key(0.42, FISH_HOLD, "backOut"), key(0.62, REST, "quadInOut")}},
	-- QC L9: a fish that got away (or a line pulled in empty): the rod lifts on
	-- a slack line and the shoulders drop. No hook-set, no splash.
	lost = {tool = "Rod", skill = "Fishing", rod = true,
		loop = {key(0, FISH_HOLD), key(0.16, merge(FISH_HOLD, {rightArm = {96, 0, 6}, rightElbow = {30}, neck = {6}}), "quadOut", "lost"),
			key(0.5, merge(FISH_HOLD, {rightArm = {40, 0, 8}, rightElbow = {20}, waist = {-8, 0, 0}, neck = {-14}}), "sineInOut"),
			key(0.8, REST, "quadInOut")}},
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
	-- Alchemy pour, loom weave, glassblowing, sieve.
	pour = {tool = "Flask", fx = "bubbles",
		intro = {key(0, REST), key(0.2, P.POUR_LIFT, "quadOut")},
		loop = {key(0, P.POUR_LIFT), key(0.3, P.POUR_TIP, "sineInOut"), key(0.55, P.POUR_TIP, "linear", "impact"), key(0.85, P.POUR_LIFT, "sineInOut")},
		outro = {key(0, P.POUR_LIFT), key(0.2, REST, "quadInOut")}},
	weave = {fx = "sawdust",
		intro = {key(0, REST), key(0.16, P.WEAVE_A, "quadOut")},
		loop = {key(0, P.WEAVE_A), key(0.24, P.WEAVE_B, "sineInOut"), key(0.36, P.WEAVE_BEAT, "quadIn", "impact"), key(0.6, P.WEAVE_A, "sineInOut")},
		outro = {key(0, P.WEAVE_A), key(0.2, REST, "quadInOut")}},
	blow = {tool = "Pipe", fx = "steam",
		intro = {key(0, REST), key(0.2, P.BLOW_HOLD, "quadOut")},
		loop = {key(0, P.BLOW_HOLD), key(0.25, P.BLOW_INHALE, "sineInOut"), key(0.5, P.BLOW_PUFF, "quadIn", "impact"), key(0.9, P.BLOW_HOLD, "sineInOut")},
		outro = {key(0, P.BLOW_HOLD), key(0.2, REST, "quadInOut")}},
	sift = {tool = "Sieve", fx = "dust",
		intro = {key(0, REST), key(0.16, P.SIFT_A, "quadOut")},
		loop = {key(0, P.SIFT_A), key(0.12, P.SIFT_B, "sineInOut"), key(0.24, P.SIFT_A, "sineInOut", "impact"), key(0.36, P.SIFT_B, "sineInOut"),
			key(0.48, P.SIFT_A, "sineInOut")},
		outro = {key(0, P.SIFT_A), key(0.18, REST, "quadInOut")}},
	interact = {fx = "ring",
		loop = {key(0, REST), key(0.2, REACH, "quadOut"), key(0.3, PRESS, "quadIn", "impact"), key(0.55, REST, "quadInOut")}},
	-- NPC greeting: a wave, then an open-handed nod (the NPC nods back locally).
	talk = {
		loop = {key(0, REST), key(0.2, P.WAVE_UP, "quadOut"), key(0.36, P.WAVE_A, "sineInOut"), key(0.52, P.WAVE_B, "sineInOut"),
			key(0.68, P.WAVE_A, "sineInOut", "impact"), key(0.92, P.TALK_OPEN, "quadInOut"), key(1.06, P.NOD_DOWN, "quadOut"), key(1.2, P.NOD_UP, "sineInOut"),
			key(1.32, P.NOD_DOWN, "sineInOut"), key(1.6, REST, "quadInOut")}},
	-- Chests, caches, ballot boxes and doors: grip, a dip, lift, look in.
	open = {fx = "ring", stopOnMove = true,
		loop = {key(0, REST), key(0.22, P.OPEN_GRIP, "quadOut"), key(0.32, P.OPEN_DIP, "quadIn"), key(0.6, P.OPEN_LIFT, "backOut", "impact"),
			key(0.82, P.OPEN_LOOK, "quadOut"), key(1.1, REST, "quadInOut")}},
	-- Banking / trading: reach to the purse, hand it over, set it down.
	deposit = {tool = "Pouch", fx = "coins",
		loop = {key(0, REST), key(0.18, P.POUCH, "quadOut"), key(0.42, P.HAND_OVER, "quadInOut"), key(0.54, P.HAND_SET, "quadIn", "impact"),
			key(0.66, merge(P.HAND_SET, {neck = {-14}}), "quadOut"), key(0.95, REST, "quadInOut")}},
	-- Garden plots: dig, seed, pat (plant); tip the can (water); work the soil (tend).
	plant = {fx = "dust", stopOnMove = true,
		loop = {key(0, REST), key(0.2, P.DIG_A, "quadOut"), key(0.32, P.DIG_B, "quadIn"), key(0.44, P.DIG_A, "quadOut"), key(0.56, P.DIG_B, "quadIn"),
			key(0.8, P.SEED, "quadInOut"), key(1.0, P.PAT, "quadIn", "impact"), key(1.12, P.SEED, "quadOut"), key(1.22, P.PAT, "quadIn"), key(1.5, REST, "quadInOut")}},
	water = {tool = "Can", fx = "water",
		loop = {key(0, REST), key(0.2, P.WATER_HOLD, "quadOut"), key(0.38, P.WATER_TIP, "sineInOut", "impact"), key(0.7, P.WATER_SWAY, "sineInOut", "impact"),
			key(1.0, P.WATER_TIP, "sineInOut"), key(1.15, P.WATER_HOLD, "quadOut"), key(1.4, REST, "quadInOut")}},
	tend = {fx = "dust", stopOnMove = true,
		loop = {key(0, REST), key(0.22, P.TEND_A, "quadOut"), key(0.4, P.TEND_B, "sineInOut", "impact"), key(0.58, P.TEND_A, "sineInOut"),
			key(0.76, P.TEND_B, "sineInOut"), key(1.05, REST, "quadInOut")}},
	-- Altars: kneel and pray; kneel and raise an offering.
	pray = {fx = "mend", stopOnMove = true,
		loop = {key(0, REST), key(0.4, P.PRAY, "quadOut"), key(0.9, P.PRAY_DEEP, "sineInOut", "impact"), key(1.5, P.PRAY, "sineInOut"), key(2.0, REST, "quadInOut")}},
	offer = {fx = "mend", stopOnMove = true,
		loop = {key(0, REST), key(0.38, P.OFFER_DOWN, "quadOut"), key(0.8, P.OFFER_UP, "backOut", "impact"), key(1.2, P.OFFER_UP, "sineInOut"),
			key(1.45, P.OFFER_DOWN, "quadInOut"), key(1.8, REST, "quadInOut")}},
	-- Motes and anything on the ground: stoop, grab, stow at the chest.
	pickup = {fx = "ring", stopOnMove = true,
		loop = {key(0, REST), key(0.24, P.STOOP, "quadOut"), key(0.34, P.STOOP_GRAB, "quadIn", "impact"), key(0.58, P.STOW, "quadOut"), key(0.86, REST, "quadInOut")}},
	-- Travel beacons, warps, portals and lair altars: reach out to the crystal.
	attune = {fx = "attune",
		loop = {key(0, REST), key(0.24, P.ATTUNE_REACH, "quadOut"), key(0.5, P.ATTUNE_PUSH, "sineInOut", "impact"), key(0.8, P.ATTUNE_PUSH, "sineInOut"),
			key(1.1, REST, "quadInOut")}},
	-- §49 Binding Altars: gather the shards at the chest, rise, release into the altar (rune sparks).
	bind = {fx = "bind",
		loop = {key(0, REST), key(0.3, P.BIND_GATHER, "quadOut"), key(0.62, P.BIND_RISE, "sineInOut"), key(0.8, P.BIND_RELEASE, "backOut", "impact"),
			key(1.1, P.BIND_RELEASE, "sineInOut"), key(1.45, REST, "quadInOut")}},
	-- §51 Skysailing: board a ship, take the helm, throw the salvage grapple, haul a sheet.
	board = {fx = "attune", stopOnMove = true,
		loop = {key(0, REST), key(0.2, P.BOARD_REACH, "quadOut"), key(0.42, P.BOARD_STEP, "quadIn", "impact"), key(0.66, P.BOARD_UP, "quadOut"),
			key(0.95, REST, "quadInOut")}},
	helm = {
		loop = {key(0, REST), key(0.22, P.HELM_GRIP, "quadOut"), key(0.5, P.HELM_LEFT, "sineInOut"), key(0.8, P.HELM_RIGHT, "sineInOut", "impact"),
			key(1.05, P.HELM_GRIP, "sineInOut"), key(1.3, REST, "quadInOut")}},
	grapple = {fx = "dust",
		loop = {key(0, REST), key(0.28, P.GRAPPLE_WIND, "quadOut"), key(0.44, P.GRAPPLE_THROW, "backOut", "impact"), key(0.7, P.HAUL_HIGH, "quadOut"),
			key(0.95, P.HAUL_LOW, "quadIn"), key(1.2, P.HAUL_HIGH, "quadOut"), key(1.45, P.HAUL_LOW, "quadIn"), key(1.75, REST, "quadInOut")}},
	haul = {
		loop = {key(0, REST), key(0.2, P.HAUL_HIGH, "quadOut"), key(0.42, P.HAUL_LOW, "quadIn", "impact"), key(0.62, P.HAUL_HIGH, "quadOut"),
			key(0.82, P.HAUL_LOW, "quadIn"), key(1.1, REST, "quadInOut")}},
	read = {
		loop = {key(0, REST), key(0.24, P.READ, "quadOut"), key(0.6, P.READ_TURN, "sineInOut", "impact"), key(0.84, P.READ, "sineInOut"), key(1.2, REST, "quadInOut")}},
	survey = {
		loop = {key(0, REST), key(0.26, P.SHADE, "quadOut"), key(0.8, P.SHADE_R, "sineInOut", "impact"), key(1.2, P.SHADE, "sineInOut"), key(1.5, REST, "quadInOut")}},
	pilfer = {
		loop = {key(0, REST), key(0.14, P.PILFER_LEAN, "quadOut"), key(0.24, P.PILFER_GRAB, "quadIn", "impact"), key(0.4, P.POUCH, "quadOut"), key(0.66, REST, "quadInOut")}},
	attack = {tool = "Sword", shake = true, hitstop = 0.045, sound = "slash", combo = {window = 0.9, hitstops = {0.04, 0.045, 0.08}}, variants = {
		{key(0, REST), key(0.1, P.SW1_COIL, "quadOut"), key(0.18, P.SW1_HIT, "quadIn", "impact"), key(0.27, P.SW1_FOLLOW, "quadOut"), key(0.48, REST, "sineInOut")},
		{key(0, REST), key(0.09, P.SW2_COIL, "quadOut"), key(0.17, P.SW2_HIT, "quadIn", "impact"), key(0.26, P.SW2_FOLLOW, "quadOut"), key(0.46, REST, "sineInOut")},
		{key(0, REST), key(0.06, P.SW3_DIP, "quadOut"), key(0.18, P.SW3_COIL, "quadOut"), key(0.28, P.SW3_HIT, "quadIn", "impact"), key(0.38, P.SW3_FOLLOW, "quadOut"),
			key(0.62, REST, "sineInOut")},
	}},
	-- Weapon classes: daggers stab / backhand, greatblades and mauls cleave
	-- overhead or sweep two-handed, glaives lunge or sweep (Data.Held.ATTACK).
	thrust = {tool = "Sword", shake = true, hitstop = 0.035, sound = "lunge", combo = {window = 0.7, hitstops = {0.025, 0.025, 0.05}}, variants = {
		{key(0, REST), key(0.06, STAB_BACK, "quadOut"), key(0.12, STAB_HIT, "quadIn", "impact"), key(0.18, P.STAB_FOLLOW, "quadOut"), key(0.32, REST, "sineInOut")},
		{key(0, REST), key(0.06, P.STAB2_BACK, "quadOut"), key(0.12, P.STAB2_HIT, "quadIn", "impact"), key(0.18, P.STAB2_FOLLOW, "quadOut"), key(0.32, REST, "sineInOut")},
		{key(0, REST), key(0.08, SLIT_BACK, "quadOut"), key(0.15, SLIT_HIT, "quadIn", "impact"), key(0.24, P.SLIT_FOLLOW, "quadOut"), key(0.4, REST, "sineInOut")},
	}},
	cleave = {tool = "Sword", shake = true, hitstop = 0.07, sound = "slash", fx = "chips", combo = {window = 1.3, hitstops = {0.08, 0.065}}, variants = {
		{key(0, REST), key(0.08, P.CLEAVE_DIP, "quadOut"), key(0.22, CLEAVE_UP, "quadOut"), key(0.32, CLEAVE_HIT, "quadIn", "impact"),
			key(0.44, P.CLEAVE_FOLLOW, "quadOut"), key(0.72, REST, "sineInOut")},
		{key(0, REST), key(0.08, P.SWEEP_COIL, "quadOut"), key(0.2, SWEEP_BACK, "quadOut"), key(0.31, SWEEP_HIT, "quadIn", "impact"),
			key(0.42, P.SWEEP_FOLLOW, "quadOut"), key(0.68, REST, "sineInOut")},
	}},
	lunge = {tool = "Sword", shake = true, hitstop = 0.05, sound = "lunge", combo = {window = 1.0, hitstops = {0.05, 0.05}}, variants = {
		{key(0, REST), key(0.08, P.LUNGE_COIL, "quadOut"), key(0.16, LUNGE_BACK, "quadOut"), key(0.25, LUNGE_HIT, "quadIn", "impact"),
			key(0.34, P.LUNGE_FOLLOW, "quadOut"), key(0.56, REST, "sineInOut")},
		{key(0, REST), key(0.1, P.SWEEP_COIL, "quadOut"), key(0.22, SWEEP_BACK, "quadOut"), key(0.34, SWEEP_HIT, "quadIn", "impact"),
			key(0.46, P.SWEEP_FOLLOW, "quadOut"), key(0.7, REST, "sineInOut")},
	}},
	eat = {tool = "Food", fx = "crumbs",
		loop = {key(0, REST), key(0.22, EAT_UP, "quadOut"), key(0.34, EAT_BITE, "quadIn", "impact"), key(0.46, P.EAT_CHEW, "sineInOut"),
			key(0.6, EAT_BITE, "quadIn", "impact"), key(0.74, P.EAT_CHEW, "sineInOut"), key(1.0, REST, "quadInOut")}},
	drink = {tool = "Flask",
		loop = {key(0, REST), key(0.25, DRINK_UP, "quadOut"), key(0.45, DRINK_TIP, "sineInOut"), key(0.75, P.DRINK_DEEP, "sineInOut", "impact"),
			key(0.9, P.DRINK_WIPE, "quadOut"), key(1.15, REST, "quadInOut")}},
	-- Combat styles (combat.client.lua): bow shot, staff cast, wand flick, Mend.
	shoot = {tool = "Bow", hand = "left", sound = "bow",
		loop = {key(0, REST), key(0.12, BOW_RAISE, "quadOut"), key(0.3, BOW_DRAW, "quadInOut"), key(0.36, P.BOW_ANCHOR, "sineInOut"),
			key(0.4, BOW_LOOSE, "quadOut", "release"), key(0.5, P.BOW_FOLLOW, "quadOut"), key(0.72, REST, "quadInOut")}},
	cast = {tool = "Staff", fx = "ring", sound = "cast",
		loop = {key(0, REST), key(0.08, P.STAFF_GATHER, "quadOut"), key(0.18, STAFF_RAISE, "quadOut"), key(0.32, STAFF_THRUST, "backOut", "impact"),
			key(0.42, P.STAFF_FOLLOW, "quadOut"), key(0.66, REST, "quadInOut")}},
	flick = {tool = "Wand", fx = "ring",
		loop = {key(0, REST), key(0.06, P.WAND_COIL, "quadOut"), key(0.14, WAND_UP, "quadOut"), key(0.2, WAND_FLICK, "quadIn", "impact"),
			key(0.28, P.WAND_FOLLOW, "quadOut"), key(0.44, REST, "quadInOut")}},
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
	-- Beaconry: strike the striker down across the tinder (sparks at the impact).
	kindle = {tool = "Striker", fx = "sparks", minCycles = 2,
		intro = {key(0, REST), key(0.2, KINDLE_READY, "quadOut")},
		loop = {key(0, KINDLE_READY), key(0.16, KINDLE_UP, "quadOut"), key(0.24, KINDLE_STRIKE, "quadIn", "impact"), key(0.42, KINDLE_READY, "sineInOut")},
		outro = {key(0, KINDLE_READY), key(0.24, REST, "quadInOut")}},
	netswing = {tool = "Net", fx = "ring",
		loop = {key(0, REST), key(0.16, NET_BACK, "quadOut"), key(0.32, NET_SWEEP, "quadIn", "impact"), key(0.62, REST, "quadInOut")}},
	-- Death (observed: every client plays it from the replicated Humanoid.Died).
	death = {observed = true, dead = true,
		intro = {key(0, REST), key(0.22, P.DEATH_BUCKLE, "quadIn"), key(0.6, P.DEATH_FALL, "quadOut", "impact")},
		loop = {key(0, P.DEATH_FALL), key(1, P.DEATH_FALL)},
		outro = {key(0, P.DEATH_FALL), key(0.3, REST, "quadInOut")}},
}

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
-- §47: the anvil hammers, the cauldron pours and stirs, the loom weaves, the furnace blows glass.
Core.STATION_GESTURE = {Forge = {"hammer"}, Cauldron = {"pour", "stir"}, Hearth = {"flip", "stir"}, Workbench = {"hammer", "saw"}, Slayer = {"talk"}}
-- Crafting stations (prompt action "craftStation": Jeweller's Bench, Tanning Rack, Glass Furnace)
-- use Data.Crafting.Stations[id].gesture (QC L8).
-- Every prompt verb (IsleAction) the servers build maps to a gesture here;
-- verify-animations.luau scans the server sources and fails on a verb that
-- would fall through to the generic reach.
Core.ACTION_GESTURE = {fight = "attack", worker = "hammer", workerBuild = "hammer", decorate = "hammer", homeExpand = "hammer",
	trap = "settrap", net = "netswing",
	lairEnter = "attune", lairLeave = "attune", raidLeave = "attune", -- summoning altars, arena and vault exits
	raidAct = "interact", -- Undertide levers and plates: reach and press
	beaconLight = "interact", -- Beaconry: the pyre hold reaches in; the strike plays once from BeaconryGesture (QC L3)
	bank = "deposit", sell = "deposit", skillVendor = "deposit", eventVendor = "deposit",
	claim = "open", workerClaim = "open", councilView = "open",
	explore = "survey", landmark = "survey",
	altarPray = "pray", moteShrine = "pray", altarOffer = "offer", bossSigil = "offer",
	moteCollect = "pickup", thieve = "pilfer",
	logsBoard = "read", lecternVisit = "read", raidPortal = "read", factionBoard = "talk",
	gardenOpen = "read", gardenPlot = "tend",
	-- §49 Runebinding: altars bind, waygates / the Shardgate / the Rift entry attune,
	-- the Rift workbench hammers, the guardian portals take an offering.
	runeAltar = "bind", rbGate = "attune", rbWaygate = "attune", rbTravel = "attune", riftJoin = "attune",
	riftShape = "hammer", riftCharge = "offer",
	-- §51 Skysailing: the slip hammers, docks and gangways board, harbour boards read.
	shipwright = "hammer", sailLaunch = "board", sailBoard = "board", harbourBoard = "read",
	-- §53 The Sundered Sky: set pieces are surveyed; mirrors, gates / the Loomheart / arena exits attuned.
	storyInspect = "survey", storyPuzzle = "attune", storyBoss = "attune", storyLeave = "attune", storyWarp = "attune"}
-- Per-item refinements (the garden's composter lid, its visiting traders).
Core.ITEM_GESTURE = {gardenOpen = {composter = "open", visitor = "talk", ledger = "read"}}
-- Garden plots do whatever the plot needs (plant, water, harvest, treat): the
-- gesture waits for the server's reply message (Core.replyGesture).
Core.DEFERRED_ACTION = {gardenPlot = true}
-- Prompts without an IsleAction (travel posts, NPC talk, expedition and
-- minigame prompts) pick by their action text.
Core.TEXT_GESTURE = {{"^Talk", "talk"}, {"^Hail", "talk"}, {"^Speak", "talk"}, {"^Trade", "deposit"}, {"^Vote", "deposit"},
	{"^Travel", "attune"}, {"^Return", "attune"}, {"^Ride", "attune"}, {"^Step", "attune"}, {"^Board", "attune"}, {"^Visit", "attune"},
	{"^Ascend", "attune"}, {"^Descend", "attune"}, {"^Enter", "attune"}, {"^Leave", "attune"}, {"^Tune", "attune"},
	{"^Strike", "attack"}, {"^Ranged", "shoot"}, {"^Class ability", "cast"}, {"^Ultimate", "cast"}, {"^Harpoon", "thrust"},
	{"^Catch", "reel"}, {"^Cook", "flip"}, {"^Open", "open"}, {"^Claim", "open"}, {"^Read", "read"}, {"^Study", "read"}, {"^Plan", "read"},
	{"^Toggle", "interact"}, {"^Pray", "pray"}, {"^Collect", "pickup"}, {"^Pick", "pickup"}}
-- Agility prompts animate from the AgilityMove attribute the server sets instead.
Core.SILENT_ACTION = {agility = true, shortcut = true}

-- info = {action, item, coopResource, text (ActionText), role (TownsfolkRole)};
-- counter alternates station variants. Returns name, source ("action",
-- "text", "role" or "fallback": the generic reach).
function Core.selectGesture(info, Data, counter)
	local action, item = info.action, info.item
	if Core.SILENT_ACTION[action] then return nil end
	if info.coopResource and Core.COOP_GESTURE[info.coopResource] then return Core.COOP_GESTURE[info.coopResource], "action" end
	if action == "gather" and type(item) == "string" then
		local skill = Data.ResourceSkill[item]
		return Core.SKILL_GESTURE[skill] or "interact", if Core.SKILL_GESTURE[skill] then "action" else "fallback"
	end
	-- QC L8: Crafting stations read their gesture list from Data.Crafting.Stations.
	local crafted = action == "craftStation" and Data.Crafting and Data.Crafting.Stations and Data.Crafting.Stations[item]
	local list = (crafted and type(crafted.gesture) == "table" and #crafted.gesture > 0 and crafted.gesture)
		or ((action == "station" or action == "craftStation") and Core.STATION_GESTURE[item])
	if list then
		return list[((counter or 0) % #list) + 1], "action"
	end
	if action == "craft" then
		local recipe = Data.Recipes and Data.Recipes[item]
		local station = recipe and recipe.station
		if item == "Tonic" or station == "Cauldron" then return "stir", "action" end
		if station == "Hearth" then return "flip", "action" end
		return "hammer", "action"
	end
	local byItem = Core.ITEM_GESTURE[action]
	if byItem and byItem[item] then return byItem[item], "action" end
	if Core.ACTION_GESTURE[action] then return Core.ACTION_GESTURE[action], "action" end
	if action == nil and type(info.role) == "string" then return "talk", "role" end
	if action == nil and type(info.text) == "string" then
		for _, rule in ipairs(Core.TEXT_GESTURE) do
			if info.text:find(rule[1]) then return rule[2], "text" end
		end
	end
	return "interact", "fallback"
end
-- A deferred garden prompt's reply message → plant / water / harvest / tend.
function Core.replyGesture(message)
	if type(message) ~= "string" then return "tend" end
	if message:find("^Planted") then return "plant" end
	if message:find("^Watered") then return "water" end
	if message:find("Farming XP") then return "harvest" end
	return "tend"
end

-- Stances (§47): the node's height against the root picks the variant, so a
-- rock at the feet is struck from a crouch and a high vein overhead. Every
-- client derives it from the relayed target part, so only the base relays.
Core.STANCES = {mine = {low = "mine_low", lowTop = -0.6, high = "mine_high", highCentre = 1.8},
	chop = {low = "chop_low", lowTop = 0.2}, harvest = {high = "harvest_high", highTop = 1.0}}
function Core.stanceFor(name, rootY, partY, sizeY)
	local set = Core.STANCES[name]
	if not set or type(rootY) ~= "number" or type(partY) ~= "number" then return name end
	local top = partY + (tonumber(sizeY) or 0) / 2 - rootY
	local centre = partY - rootY
	if set.low and top < set.lowTop then return set.low end
	if set.high and ((set.highCentre and centre > set.highCentre) or (set.highTop and top > set.highTop)) then return set.high end
	return name
end
-- The relayed / held-item name a gesture answers to (stances → base, the
-- reel / bite one-shots → fish).
Core.FIT_AS = {reel = "fish", bite = "fish", lost = "fish"}
function Core.fitName(name)
	local def = Core.GESTURES[name]
	return (def and def.base) or Core.FIT_AS[name] or name
end

-- Combos (§47): consecutive attacks inside the window chain the variants in
-- order (sword: forehand, backhand, overhead finisher); a pause restarts at 1.
function Core.newCombo() return {name = nil, step = 0, at = -math.huge} end
function Core.comboNext(rec, name, now)
	local def = Core.GESTURES[name]
	if not def or not def.combo or not def.variants then return 1 end
	if rec.name == name and now - rec.at <= def.combo.window then rec.step = rec.step % #def.variants + 1 else rec.step = 1 end
	rec.name, rec.at = name, now
	return rec.step
end
-- Tier flourish (§47): 0 below tier 4, 1 for tiers 4-6 (a wrist twirl after
-- the last strike, more chips), 2 from tier 7 (plus a glint).
function Core.flourishLevel(Data, itemId)
	local def = type(itemId) == "string" and Data.Items[itemId]
	if not def or not Data.Held or not Data.Held.look then return 0 end
	local tier = tonumber(Data.Held.look(def).tier) or 0
	return if tier >= 7 then 2 elseif tier >= 4 then 1 else 0
end
Core.FLOURISH_FX = {1, 1.5, 2}

-- Rod bend (§47): degrees the blank flexes toward the water. The cast loads
-- it back and whips it through, the wait bobs it, a bite snaps it down and the
-- reel holds the fish's pull. Applied to the rod's welds (Core.bendC0).
Core.ROD_PIVOT = -0.9 -- grip-frame Z where the blank leaves the grip
Core.ROD_PARTS = {Rod = true, Guide = true, Tip = true, Line = true, Bobber = true}
Core.BITE_TIME = 0.5
function Core.rodBend(s, now)
	local t = now - s.phaseStart
	local bend = 0
	if s.name == "lost" then
		bend = -6 * math.max(0, 1 - t / 0.5) -- QC L9: a slack line
	elseif s.name == "reel" then
		bend = 30 * math.max(0, 1 - t / 0.86)
	elseif s.name == "bite" then
		bend = 22 * math.max(0, 1 - math.abs(t - 0.2) / 0.3)
	elseif s.phase == "intro" then
		if t < 0.34 then bend = -8 * t / 0.34
		elseif t < 0.46 then bend = -8 + 26 * (t - 0.34) / 0.12
		else bend = 18 * math.max(0, 1 - (t - 0.46) / 0.3) end
	elseif s.phase == "loop" then
		bend = 5 + 3 * math.sin(t / 0.9 * 2 * math.pi)
	elseif s.phase == "outro" then
		bend = 30 * math.max(0, 1 - t / 0.6)
	end
	if s.biteAt then
		local b = now - s.biteAt
		if b >= 0 and b < Core.BITE_TIME then bend += 22 * (1 - b / Core.BITE_TIME) end
	end
	return bend
end
-- A part's weld C0 bent about the pivot (in the grip frame) by `degrees` (tip down).
function Core.bendC0(baseC0, pivot, degrees)
	return pivot * CFrame.Angles(-rad(degrees), 0, 0) * pivot:Inverse() * baseC0
end

-- Beaconry (§37): BeaconryGesture "<gesture>:<seq>[:<itemId>]" -> name, itemId|nil.
function Core.beaconryGesture(value)
	if type(value) ~= "string" then return nil end
	local name, item = string.match(value, "^(%a+):%d+:?(%w*)$")
	if not name or not Core.NAMES[name] then return nil end
	return name, if item ~= "" then item else nil
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
Core.MELEE_GESTURE = {attack = true, thrust = true, cleave = true, lunge = true}
function Core.itemFits(gesture, def)
	gesture = Core.fitName(gesture)
	if gesture == "kindle" then return def.heldClass == "striker" end -- Beaconry strikers (material items)
	local kind = Core.TOOL_ITEM_KIND[gesture]
	if kind then return def.kind == "tool" and def.toolKind == kind end
	if Core.MELEE_GESTURE[gesture] then return def.kind == "weapon" end
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
		-- Beaconry striker: a wrapped grip, a steel bar and a flint nub.
		Striker = {p("Grip", V(0.22, 0.22, 0.7), V(0, 0, -0.05), W, "Wood"), p("Steel", V(0.5, 0.16, 0.16), V(0, 0.05, -0.55), H),
			p("Flint", V(0.34, 0.34, 0.34), V(0, 0.24, -0.72), "string", "Slate", "Ball")},
		-- §47 station and interaction props: glassblowing pipe, sand sieve,
		-- watering can, coin purse.
		Pipe = {p("Pipe", V(0.14, 0.14, 3.2), V(0, 0, -1.2), H), p("Gather", V(0.55, 0.55, 0.55), V(0, 0, -2.9), "string", "Glass", "Ball")},
		Sieve = {p("Rim", V(1.6, 0.2, 1.6), V(0, 0, -0.9), W, "Wood"), p("Mesh", V(1.4, 0.05, 1.4), V(0, 0.02, -0.9), "string", "Fabric")},
		Can = {p("Body", V(0.7, 0.8, 0.9), V(0, 0.1, -0.5), H), p("Spout", V(0.12, 0.12, 0.9), V(0, 0.25, -1.3), H),
			p("Rose", V(0.26, 0.26, 0.1), V(0, 0.3, -1.75), H)},
		Pouch = {p("Pouch", V(0.55, 0.6, 0.5), V(0, -0.1, -0.3), W, "Fabric", "Ball"), p("Tie", V(0.3, 0.12, 0.3), V(0, 0.22, -0.3), "string", "Fabric")},
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

-- Camera shake on Humanoid.CameraOffset that adds to whatever offset is there
-- (another script's, e.g. a crouch or a vehicle) and puts it back at the end.
-- If the offset is changed by someone else mid-shake, theirs is kept.
Core.SHAKE_TIME, Core.SHAKE_AMP = 0.12, 0.12
function Core.newShake()
	local K = {}
	function K.start(humanoid, now)
		if K.humanoid and K.humanoid ~= humanoid then K.stop() end
		if not K.humanoid then K.humanoid, K.base, K.written = humanoid, humanoid.CameraOffset, nil end
		K.untilAt = now + Core.SHAKE_TIME
	end
	function K.stop()
		local h = K.humanoid
		if not h then return end
		if K.written == nil or h.CameraOffset == K.written then h.CameraOffset = K.base end
		K.humanoid, K.base, K.written = nil, nil, nil
	end
	-- rand() in [0, 1).
	function K.step(now, rand)
		local h = K.humanoid
		if not h then return end
		if K.written ~= nil and h.CameraOffset ~= K.written then
			K.base = h.CameraOffset -- someone else moved it: shake around theirs
		end
		local left = K.untilAt - now
		if left <= 0 then
			K.stop()
			return
		end
		local a = Core.SHAKE_AMP * left / Core.SHAKE_TIME
		K.written = K.base + Vector3.new((rand() - 0.5) * a, (rand() - 0.5) * a, 0)
		h.CameraOffset = K.written
	end
	return K
end

-- Own auto switch still in flight (hotbar → server): the local swing treats the
-- requested item as held until the server answers. A reply naming another item
-- (refused, rate-limited) drops it at once instead of waiting for the timeout.
Core.PENDING_HOLD = 1.5
function Core.newPending()
	local P = {}
	function P.set(id, now) P.id, P.untilAt = id, now + Core.PENDING_HOLD end
	function P.get(now)
		if P.id and now < P.untilAt then return P.id end
		P.id = nil
		return nil
	end
	function P.reply(requested, heldItem)
		if P.id ~= nil and P.id == requested and heldItem ~= requested then P.id = nil end
	end
	function P.clear() P.id = nil end
	return P
end

-- Carry poses: only the cap nearest holders within range are posed (the local
-- player is always distance 0). list = array of holder records with .distance;
-- sets .admitted on each. Sorts list in place (no allocation).
local function byDistance(a, b) return a.distance < b.distance end
function Core.admitHolders(list, cap, range)
	cap, range = cap or Core.REMOTE_CAP, range or Core.REMOTE_RANGE
	table.sort(list, byDistance)
	for i, h in ipairs(list) do h.admitted = i <= cap and h.distance <= range end
end

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

-- Body layer (§47) ------------------------------------------------------------
-- Additive on top of the Animator and any gesture: a landing squash after a
-- real fall, a forward lean at a sprint and a flinch when hurt. Everything is
-- derived from what every client already sees (root velocity, Humanoid
-- health), so nothing is relayed. One record per posed character; the pose is
-- written into the record's own buffer (no per-frame tables).
Core.LAND_MIN_SPEED, Core.LAND_FULL_SPEED, Core.LAND_TIME = 28, 80, 0.42
Core.FLINCH_TIME = 0.32
Core.LEAN_MAX, Core.SPRINT_FROM, Core.SPRINT_FULL = 10, 17.5, 28
Core.BODY_CAP = Core.REMOTE_CAP -- remote bodies posed at once (nearest win; the local one always)
-- Reduced motion keeps the cues but calms them: smaller squash / lean /
-- flinch, no idle fidgets, no tier flourish, no hit-stop or camera shake.
Core.REDUCED = {land = 0.4, lean = 0.5, flinch = 0.5, fidgets = false, flourish = false}
Core.IDLE_AFTER, Core.FIDGET_GAP = 6, {9, 15}
function Core.newBody()
	return {minVy = 0, land = nil, landAmp = 0, flinch = nil, flinchAmp = 0, lean = 0, buf = Core.poseBuffer(), active = false}
end
-- Feed one frame of root velocity. Returns true on a landing.
function Core.bodyFeed(b, vy, horizontal, now, dt, reduced)
	local landed = false
	if vy < -Core.LAND_MIN_SPEED then b.minVy = math.min(b.minVy, vy) end
	if b.minVy < 0 and vy > -4 then
		local amp = math.clamp((-b.minVy - Core.LAND_MIN_SPEED) / (Core.LAND_FULL_SPEED - Core.LAND_MIN_SPEED), 0.25, 1)
		b.land, b.landAmp, b.minVy = now, amp * (if reduced then Core.REDUCED.land else 1), 0
		landed = true
	end
	local target = math.clamp((horizontal - Core.SPRINT_FROM) / (Core.SPRINT_FULL - Core.SPRINT_FROM), 0, 1)
	if math.abs(vy) > 8 then target = 0 end -- airborne: no lean
	if reduced then target *= Core.REDUCED.lean end
	b.lean += (target - b.lean) * math.min(1, dt * 6)
	return landed
end
-- Health dropped by `fraction` of max: flinch (stronger for bigger hits).
function Core.bodyHit(b, fraction, now, reduced)
	b.flinch = now
	b.flinchAmp = math.clamp(0.35 + (tonumber(fraction) or 0) * 4, 0.35, 1) * (if reduced then Core.REDUCED.flinch else 1)
end
-- 0 → 1 fast, then back to 0 by `total` (a squash / flinch envelope).
function Core.envelope(t, attack, total)
	if t < 0 or t >= total then return 0 end
	if t < attack then return Core.ease.quadOut(t / attack) end
	local u = (t - attack) / (total - attack)
	return (1 - u) * (1 - u)
end
local function addJoint(buf, joint, rx, ry, rz, y)
	local v = buf.out[joint]
	if not v then
		v = poseSlot(buf, joint)
		for k = 1, 6 do v[k] = 0 end
		buf.out[joint] = v
	end
	v[1] += rx; v[2] += ry; v[3] += rz; v[5] += y or 0
end
-- The additive pose for this frame (buf.out) and whether anything is active.
function Core.bodyPose(b, now)
	local buf = b.buf
	table.clear(buf.out)
	local any = false
	local land = if b.land then Core.envelope(now - b.land, 0.07, Core.LAND_TIME) * b.landAmp else 0
	if b.land and now - b.land >= Core.LAND_TIME then b.land = nil end
	if land > 0.001 then
		any = true
		addJoint(buf, "rightHip", 34 * land, 0, 0); addJoint(buf, "leftHip", 30 * land, 0, 0)
		addJoint(buf, "rightKnee", -56 * land, 0, 0); addJoint(buf, "leftKnee", -52 * land, 0, 0)
		addJoint(buf, "root", 0, 0, 0, -0.5 * land); addJoint(buf, "waist", -12 * land, 0, 0); addJoint(buf, "neck", -6 * land, 0, 0)
		addJoint(buf, "rightArm", 0, 0, 10 * land); addJoint(buf, "leftArm", 0, 0, -10 * land)
	end
	if b.lean > 0.01 then
		any = true
		local deg = Core.LEAN_MAX * b.lean
		addJoint(buf, "waist", -deg, 0, 0); addJoint(buf, "neck", 0.6 * deg, 0, 0)
	end
	local flinch = if b.flinch then Core.envelope(now - b.flinch, 0.05, Core.FLINCH_TIME) * b.flinchAmp else 0
	if b.flinch and now - b.flinch >= Core.FLINCH_TIME then b.flinch = nil end
	if flinch > 0.001 then
		any = true
		addJoint(buf, "waist", 9 * flinch, 4 * flinch, 0); addJoint(buf, "neck", 12 * flinch, 0, 0)
		addJoint(buf, "rightArm", 14 * flinch, 0, 8 * flinch); addJoint(buf, "leftArm", 14 * flinch, 0, -8 * flinch)
		addJoint(buf, "root", 0, 0, 0, -0.1 * flinch)
	end
	return buf.out, any
end
-- Idle fidget timing: due after IDLE_AFTER s standing still with an item in
-- hand, then every FIDGET_GAP (rand in [0, 1)).
function Core.fidgetDue(b, now, still, rand)
	if not still then
		b.stillSince, b.nextFidget = nil, nil
		return false
	end
	b.stillSince = b.stillSince or now
	if now - b.stillSince < Core.IDLE_AFTER then return false end
	if not b.nextFidget then b.nextFidget = now end
	if now < b.nextFidget then return false end
	b.nextFidget = now + Core.FIDGET_GAP[1] + (Core.FIDGET_GAP[2] - Core.FIDGET_GAP[1]) * rand
	return true
end
-- QC M2: the additive layer. Every motor written last frame is put back to
-- the base it had (RunService.PreAnimation, before the Animator), and offsets
-- are applied on top of this frame's Transform in Stepped, so nothing
-- accumulates on joints the Animator does not rewrite and no earlier offset
-- bleeds into the gesture fade lerps. No equality tests on CFrames.
function Core.bodyRestore(b)
	for _, e in ipairs(b.entries) do
		if e.written then
			if e.motor.Parent then e.motor.Transform = e.base end
			e.base, e.written = nil, nil
		end
	end
end
function Core.bodyApply(b, pose)
	for _, e in ipairs(b.entries) do
		local touched = false
		for _, part in ipairs(e.parts) do
			if pose[part[1]] then touched = true; break end
		end
		if touched then
			local base = e.motor.Transform
			e.base, e.written = base, true
			e.motor.Transform = base * Core.motorTarget(e, pose)
		end
	end
end
-- QC L3: no body layer while dead, seated or platform-standing (vehicles, stuns).
function Core.bodySkip(humanoid)
	return humanoid == nil or humanoid.Health <= 0 or humanoid.Sit == true or humanoid.PlatformStand == true
end
-- QC L4: a drop caused only by MaxHealth shrinking (gear removed, a buff ending
-- clamps Health) is not a hit.
function Core.isHit(prev, health, prevMax, max)
	if not (health < prev and health > 0) then return false end
	if max < prevMax and health >= max - 1e-3 then return false end
	return true
end
-- QC L11: a rig binding is stale once any motor lost its parent (respawned limb, package swap).
function Core.needsRebind(entries)
	if not entries or #entries == 0 then return true end
	for _, e in ipairs(entries) do
		if not e.motor.Parent then return true end
	end
	return false
end
-- QC M4: corpses within REMOTE_RANGE always play the collapse (whatever the
-- body cap); farther ones break their joints locally (the default ragdoll).
function Core.deathPlan(isLocal, distance)
	if isLocal or (tonumber(distance) or math.huge) <= Core.REMOTE_RANGE then return "play" end
	return "break"
end

-- NPC nod (talk): degrees on the NPC's Neck Transform over NOD_TIME.
Core.NOD_TIME = 0.9
function Core.nodCurve(t)
	if t < 0 or t >= Core.NOD_TIME then return 0 end
	return -14 * math.sin(t / Core.NOD_TIME * 2 * math.pi) * (1 - t / Core.NOD_TIME) - 4 * math.sin(t / Core.NOD_TIME * math.pi)
end

-- Human joint ranges (degrees per axis, studs for offsets) every keyframe
-- stays inside; verify-animations.luau sweeps every pose against them.
Core.JOINT_LIMITS = {
	rightArm = {{-65, 180}, {-100, 100}, {-100, 100}}, leftArm = {{-65, 180}, {-100, 100}, {-100, 100}},
	rightElbow = {{0, 150}, {0, 0}, {0, 0}}, leftElbow = {{0, 150}, {0, 0}, {0, 0}},
	rightWrist = {{-90, 90}, {-90, 90}, {-90, 90}},
	waist = {{-55, 35}, {-55, 55}, {-30, 30}}, neck = {{-45, 45}, {-60, 60}, {-30, 30}},
	root = {{-30, 30}, {-30, 30}, {-30, 30}, offset = {-2.2, 0.6}},
	rightHip = {{-45, 125}, {-45, 45}, {-45, 45}}, leftHip = {{-45, 125}, {-45, 45}, {-45, 45}},
	rightKnee = {{-150, 0}, {0, 0}, {0, 0}}, leftKnee = {{-150, 0}, {0, 0}, {0, 0}},
}

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
			-- QC L6: the basis inverse is cached at bind; axis-aligned (R15) bases skip the conversion.
			-- QC L10: `legs` marks motors that carry the legs / root (released while moving).
			local basis = Core.basisOf(motor.C0)
			local legs = false
			for _, part in ipairs(spec[2]) do if Core.LEG_JOINTS[part[1]] then legs = true end end
			table.insert(entries, {motor = motor, parts = spec[2], basis = basis, basisInv = basis:Inverse(),
				identity = basis:FuzzyEq(IDENTITY, 1e-6), legs = legs})
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
local function zeroPose(v)
	return (v[1] or 0) == 0 and (v[2] or 0) == 0 and (v[3] or 0) == 0 and (v[4] or 0) == 0 and (v[5] or 0) == 0 and (v[6] or 0) == 0
end
function Core.motorTarget(entry, pose)
	-- QC L6: no identity seed, zero joints skipped, cached basis inverse.
	local r = nil
	for _, part in ipairs(entry.parts) do
		local v = pose[part[1]]
		if v and not zeroPose(v) then
			local c = Core.jointCFrame(v, part[2])
			r = if r then r * c else c
		end
	end
	if not r then return IDENTITY end
	if entry.identity then return r end
	return Core.toJointSpace(r, entry.basis, entry.basisInv)
end

-- Held items (§26): a light carrying pose per held class while nothing else
-- animates the arm (forearm raised so the blade / haft stands up-forward;
-- greatblades and mauls rest on the shoulder, staves and glaives stand upright).
local CARRY = {rightArm = {18, 0, 6}, rightElbow = {62}}
local SHOULDER = {rightArm = {30, 0, 8}, rightElbow = {105}}
local UPRIGHT = {rightArm = {8, 0, 6}, rightElbow = {82}}
local BOW_CARRY = {leftArm = {10, 0, -6}, leftElbow = {78}}
Core.HOLD_POSE = {sword = CARRY, dagger = CARRY, pickaxe = CARRY, hatchet = CARRY, hoe = CARRY, hammer = CARRY,
	greatblade = SHOULDER, maul = SHOULDER, glaive = UPRIGHT, staff = UPRIGHT,
	rod = {rightArm = {20, 0, 6}, rightElbow = {55}}, wand = {rightArm = {12, 0, 6}, rightElbow = {50}},
	shortbow = BOW_CARRY, longbow = BOW_CARRY, shield = {leftArm = {20, 0, -10}, leftElbow = {70}},
	striker = CARRY} -- Beaconry flint striker
-- §47 idle fidgets with a held item: observed (each client plays them for the
-- holders it poses, from what it sees), start and end on the class's carry pose.
local ROD_CARRY = Core.HOLD_POSE.rod
local function fidget(carry, keys) return {observed = true, fidget = true, carry = carry, loop = keys} end
Core.GESTURES.fidget_blade = fidget(CARRY, {key(0, CARRY), key(0.25, P.TWIRL, "quadOut"), key(0.45, merge(P.TWIRL, {rightWrist = {0, 0, 75}}), "sineInOut"),
	key(0.65, merge(P.TWIRL, {rightWrist = {0, 0, -60}}), "sineInOut"), key(0.85, P.TWIRL, "sineInOut"), key(1.15, CARRY, "quadInOut")})
Core.GESTURES.fidget_heavy = fidget(SHOULDER, {key(0, SHOULDER), key(0.4, P.HEAVY_REST, "quadOut"),
	key(0.8, merge(P.HEAVY_REST, {neck = {0, -20, 0}, waist = {0, 0, -4}}), "sineInOut"), key(1.2, SHOULDER, "quadInOut")})
Core.GESTURES.fidget_tool = fidget(CARRY, {key(0, CARRY), key(0.3, P.TAP_A, "quadOut"), key(0.42, P.TAP_B, "quadIn"), key(0.54, P.TAP_A, "quadOut"),
	key(0.66, P.TAP_B, "quadIn"), key(1.0, CARRY, "quadInOut")})
Core.GESTURES.fidget_bow = fidget(BOW_CARRY, {key(0, BOW_CARRY), key(0.35, P.STRING_CHECK, "quadOut"),
	key(0.5, merge(P.STRING_CHECK, {rightArm = {60, 30, 0}}), "quadIn"), key(0.7, P.STRING_CHECK, "quadOut"), key(1.1, BOW_CARRY, "quadInOut")})
Core.GESTURES.fidget_staff = fidget(UPRIGHT, {key(0, UPRIGHT), key(0.3, P.STAFF_TAP_UP, "quadOut"), key(0.42, P.STAFF_TAP, "quadIn"),
	key(0.7, P.STAFF_TAP_UP, "quadOut"), key(1.0, UPRIGHT, "quadInOut")})
Core.GESTURES.fidget_rod = fidget(ROD_CARRY, {key(0, ROD_CARRY), key(0.35, P.LINE_CHECK, "quadOut"),
	key(0.6, merge(P.LINE_CHECK, {leftElbow = {100}}), "sineInOut"), key(0.85, P.LINE_CHECK, "sineInOut"), key(1.2, ROD_CARRY, "quadInOut")})
Core.FIDGET = {sword = "fidget_blade", dagger = "fidget_blade", wand = "fidget_blade", greatblade = "fidget_heavy", maul = "fidget_heavy",
	shield = "fidget_heavy", pickaxe = "fidget_tool", hatchet = "fidget_tool", hoe = "fidget_tool", hammer = "fidget_tool", striker = "fidget_tool",
	shortbow = "fidget_bow", longbow = "fidget_bow", staff = "fidget_staff", glaive = "fidget_staff", rod = "fidget_rod"}
Core.NAMES = {}
for name in pairs(Core.GESTURES) do Core.NAMES[name] = true end
-- Motors the pose drives and their fixed targets (computed once per character/class).
function Core.holdTargets(rig, pose)
	local out = {}
	for _, entry in ipairs(rig) do
		for _, part in ipairs(entry.parts) do
			if pose[part[1]] then
				table.insert(out, {motor = entry.motor, target = Core.motorTarget(entry, pose)})
				break
			end
		end
	end
	return out
end
-- Swing sounds (built-in engine sounds; a missing entry is a silent hook only).
Core.SOUNDS = {slash = "rbxasset://sounds/swordslash.wav", lunge = "rbxasset://sounds/swordlunge.wav",
	bow = "rbxasset://sounds/swordlunge.wav", cast = "rbxasset://sounds/electronicpingshort.wav"}

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
		if s.hidHeld then s.hidHeld = nil; deps.hideHeld(character, false) end
		if deps.ended then deps.ended(s) end
		if abrupt and s.weight > 0.01 then
			for _, entry in ipairs(s.rig) do entry.motor.Transform = CFrame.new() end
		end
		s.finished = true
	end
	function E.stop(character) remove(character, true) end
	function E.get(character) return E.active[character] end
	-- The gesture clock of a state (hit-stop lag and timed rate applied).
	local function clockOf(s, real) return s.start + (real - s.lag - s.start) * s.rate end
	-- A private copy of the state's last sampled pose (allocated per play, not per frame).
	local function snapshot(s)
		local out = s.poseBuf and s.poseBuf.out
		if not out or next(out) == nil then return nil end
		local copy = {}
		for joint, v in pairs(out) do copy[joint] = table.clone(v) end
		return copy
	end
	local function present(character, def)
		if def and def.dead then return character.Parent ~= nil end
		return deps.alive(character)
	end
	function E.play(character, name, opts)
		opts = opts or {}
		local def = Core.GESTURES[name]
		if not def or not present(character, def) then return nil end
		local current = E.active[character]
		if current and current.name == name and not current.fadeStart and opts.extend then
			-- §47: a strike that arrives during the outro rejoins at the intro,
			-- crossfading from where the arms are (no snap back to rest).
			if current.phase == "outro" and def.strike then
				local vnow = clockOf(current, deps.now())
				current.from, current.fromStart = snapshot(current), vnow
				current.phase = if def.intro then "intro" else "loop"
				current.phaseStart, current.lastT, current.cycles = vnow, -1, 0
				return current
			end
			-- QC M3: a strike inside the grace hold re-phases the loop so the
			-- impact lands IMPACT after the click (the loop waits on the ready pose).
			if current.phase == "grace" and def.strike then
				local vnow = clockOf(current, deps.now())
				current.phase, current.lastT = "loop", -1
				current.phaseStart = vnow + Core.STRIKE_INTRO
				return current
			end
			-- QC M1: a held gesture (an observer's cast) only refreshes its bound;
			-- repeated relays must not queue a backlog of extra loops.
			if current.holding then
				if opts.maxHold then current.holdUntil = deps.now() + opts.maxHold end
				return current
			end
			-- QC M3: the next strike loop starts INTRO after this click (never
			-- earlier than the running loop's end), so impacts track the clicks.
			if def.strike then current.nextLoopAt = clockOf(current, deps.now()) + Core.STRIKE_INTRO end
			current.extra += 1
			return current
		end
		-- §47: a replacement crossfades from the old gesture's pose (combo chains,
		-- a cast after a swing) instead of snapping to the Animator's pose.
		local from, fromWeight = nil, 0
		if current and not current.fadeStart and current.weight > 0.05 then from, fromWeight = snapshot(current), current.weight end
		if current then remove(character, false) end
		local rig = deps.bindRig(character)
		rig = rig and Core.drivenRig(rig, def)
		if not rig or #rig == 0 then return nil end
		local now = deps.now()
		local variant = opts.variant or 1
		local hitstop = nil
		if opts.isLocal and not opts.reduced then
			hitstop = (def.combo and def.combo.hitstops and def.combo.hitstops[(variant - 1) % #def.combo.hitstops + 1]) or def.hitstop
		end
		local s = {character = character, name = name, def = def, rig = rig, holding = opts.hold == true, extra = 0, cycles = 0,
			target = opts.target, variant = variant, start = now - Core.FADE_IN * fromWeight, phaseStart = now, lastT = -1, weight = 0,
			phase = if def.intro then "intro" else "loop", isLocal = opts.isLocal == true, info = opts.info, rate = 1, lag = 0,
			hitstop = hitstop, flourish = opts.flourish, from = from, fromStart = now,
			holdUntil = if opts.maxHold then now + opts.maxHold else nil}
		-- Timed (agility moves): a fixed number of loops, scaled to end on time.
		if opts.duration then
			s.loops, s.rate = Core.timing(def, opts.duration)
			s.start = now
		end
		E.active[character] = s
		E.count += 1
		-- The held item swings itself when it fits (a pickaxe for mine, a bow for
		-- shoot); otherwise a temporary prop is shown and the held item hidden.
		if def.tool then
			if deps.heldFits and deps.heldFits(character, name) then
				s.usesHeld = true
			else
				s.tool = deps.attachTool(character, def.tool, opts.color, def.hand)
				if deps.hideHeld and deps.hideHeld(character, true) then s.hidHeld = true end
			end
		end
		s.conns = if opts.noWatch then {} else (deps.watch(character, function() E.stop(character) end) or {})
		-- A HeldItem model that arrives while the prop is out (the relay beat the
		-- auto switch's replication) must never show next to the prop: swap the
		-- prop for it when it fits the gesture, else hide it too.
		if s.tool and deps.watchHeld then
			local conn = deps.watchHeld(character, function(model) E.heldArrived(character, model) end)
			if conn then table.insert(s.conns, conn) end
		end
		s.poseBuf = Core.poseBuffer()
		return s
	end
	function E.heldArrived(character, model)
		local s = E.active[character]
		if not s or not s.tool then return end
		local fits = if deps.modelFits then deps.modelFits(model, s.name) else (deps.heldFits and deps.heldFits(character, s.name))
		if fits then
			s.tool:Destroy()
			s.tool = nil
			s.usesHeld = true
			if s.hidHeld then s.hidHeld = nil; deps.hideHeld(character, false) end
		elseif deps.hideHeld and deps.hideHeld(character, true) then
			s.hidHeld = true
		end
	end
	function E.release(character)
		local s = E.active[character]
		if s then s.holding = false end
	end
	-- QC L10: the body layer reports movement each frame.
	function E.setMoving(character, moving)
		local s = E.active[character]
		if s then s.legsOff = moving == true end
	end
	-- §47: fade the gesture out from wherever it is (walking away from a
	-- kneel, a crouch or an altar).
	function E.cancel(character)
		local s = E.active[character]
		if not s or s.fadeStart then return end
		s.lastPose = if s.poseBuf and next(s.poseBuf.out) then s.poseBuf.out else s.lastPose
		s.phase, s.fadeStart = "done", clockOf(s, deps.now())
	end
	-- The keyframes of a state's current phase (the tier flourish replaces a
	-- strike's plain outro).
	local function phaseKeys(s)
		if s.phase == "grace" then return if s.isLocal then s.def.graceLocal else s.def.graceRemote end
		if s.phase == "outro" and s.flourish and s.flourish > 0 and s.def.outroFlourish then return s.def.outroFlourish end
		return Core.keysFor(s.def, s.phase, s.variant)
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
				-- QC M1: rod gestures never re-relay per bob (one cast = one relay).
				if s.holding and deps.cycle and not s.def.rod then deps.cycle(s) end
				-- QC M3: a late strike waits on the ready pose until its own phase.
				if s.nextLoopAt then
					if s.nextLoopAt > s.phaseStart then s.phaseStart = s.nextLoopAt end
					s.nextLoopAt = nil
				end
			else
				s.phase = if s.def.graceLocal then "grace" elseif s.def.outro then "outro" else "done"
			end
		elseif s.phase == "grace" then
			s.phase = "outro"
		elseif s.phase == "outro" then
			s.phase = "done"
		end
		if s.phase == "done" then s.fadeStart = now end
	end
	function E.step()
		if E.count == 0 then return end
		local real = deps.now()
		for character, s in pairs(E.active) do
			-- Per-gesture clock: timed gestures run at s.rate from their start;
			-- a hit-stop (local impacts) holds the clock still for a few frames.
			if s.freezeUntil then
				local last = s.lastReal or real
				if last < s.freezeUntil then s.lag += math.min(real, s.freezeUntil) - last end
				if real >= s.freezeUntil then s.freezeUntil = nil end
			end
			s.lastReal = real
			local now = s.start + (real - s.lag - s.start) * s.rate
			if not present(character, s.def) then
				remove(character, true)
				continue
			end
			if s.holdUntil and real >= s.holdUntil then s.holding, s.holdUntil = false, nil end
			local keys, guard = nil, 0
			while s.phase ~= "done" and guard < 4 do
				guard += 1
				keys = phaseKeys(s)
				local dur = Core.duration(keys)
				local t = now - s.phaseStart
				local upto = math.min(t, dur)
				for _, k in ipairs(keys) do
					if k.mark and k.t > s.lastT and k.t <= upto then
						deps.mark(s, k.mark)
						if k.mark == "impact" and s.hitstop then s.freezeUntil = real + s.hitstop end
					end
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
				pose = Core.samplePose(keys, now - s.phaseStart, s.poseBuf)
				weight = math.min(1, (now - s.start) / Core.FADE_IN)
				if s.from then
					local a = (now - s.fromStart) / Core.CROSSFADE
					if a >= 1 then s.from = nil else Core.blendFrom(s.from, pose, Core.ease.quadOut(math.max(0, a)), s.poseBuf) end
				end
			end
			s.weight = weight
			-- QC L10: while the character moves, leg / root motors of a swing are
			-- left to the Animator's walk cycle (a crouch stance never skates).
			local legsOff = s.legsOff and not s.def.agility and not s.def.dead
			for _, entry in ipairs(s.rig) do
				if not (legsOff and entry.legs) then
					local target = Core.motorTarget(entry, pose)
					entry.motor.Transform = entry.motor.Transform:Lerp(target, weight)
				end
			end
			if deps.post then deps.post(s, now) end
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

-- Held items (§26). The server welds the held model (held.server.lua) and
-- publishes HeldItem; pendingHeld is our own auto switch still in flight.
local Held = Data.Held
local pending = Core.newPending()
local function bindable(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then return existing end
	local created = Instance.new("BindableEvent")
	created.Name = name
	created.Parent = ReplicatedStorage
	return created
end
-- hotbar.client.lua listens: :Fire(itemId) asks for a temporary auto switch.
local autoHold = bindable("IsleHeldAuto")
-- Sound / VFX hook for other scripts: :Fire(gesture, fx, position, isLocal).
local impactHook = bindable("IsleImpactLocal")
-- hotbar.client.lua fires (requestedId, heldItem) once an auto request settles.
bindable("IsleHeldAutoReply").Event:Connect(function(requested, heldItem) pending.reply(requested, heldItem) end)
local function heldIdOf(character)
	local who = Players:GetPlayerFromCharacter(character)
	if not who then return nil end
	if who == player then
		local id = pending.get(os.clock())
		if id then return id end
	end
	local id = who:GetAttribute("HeldItem")
	return if type(id) == "string" and id ~= "" then id else nil
end
local function heldFits(character, name)
	local id = heldIdOf(character)
	return id ~= nil and Held.fits(Core.fitName(name), Held.classOf(Data.Items[id]))
end
-- Hides (locally) the held model while a station prop or food is in the hand.
local function hideHeld(character, hidden)
	local model = character:FindFirstChild("HeldItem")
	if not model then return false end
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") then part.LocalTransparencyModifier = if hidden then 1 else 0 end
	end
	return true
end

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
	-- §47: coins (banking), watering-can drops, travel attunement, tier glint.
	coins = {count = 0.6, speed = 6, size = 0.2, material = Enum.Material.Neon, colour = "F6C453", up = true},
	water = {count = 1, speed = 5, size = 0.2, material = Enum.Material.Glass, colour = "9FD8FF"},
	attune = {count = 1, speed = 5, size = 0.26, material = Enum.Material.Neon, colour = "7FE6FF", up = true, float = true},
	bind = {count = 1.2, speed = 6, size = 0.24, material = Enum.Material.Neon, colour = "C38BFF", up = true, float = true}, -- §49 rune sparks
	glint = {count = 0.5, speed = 3, size = 0.22, material = Enum.Material.Neon, colour = "FFF4C8", float = true},
}
Core.FX_STYLE = FX_STYLE
-- QC L7: impact FX parts (and their records) are pooled: an expired chip is
-- unparented and reused by the next burst instead of destroyed / re-created.
local fxFree = {}
Core.fxFree = fxFree
local function burst(style, position, colour, reduced, scale)
	local spec = FX_STYLE[style]
	if not spec then return end
	local n = math.max(1, math.floor(Core.fxBudget(reduced) * spec.count * (scale or 1)))
	local camera = Workspace.CurrentCamera
	for i = 1, n do
		if #fxParts >= Core.MAX_FX_PARTS then return end
		local fx = table.remove(fxFree)
		if not fx then
			local made = Instance.new("Part")
			made.Anchored, made.CanCollide, made.CanQuery, made.CanTouch, made.CastShadow = true, false, false, false, false
			fx = {part = made}
		end
		local part = fx.part
		part.Transparency = 0
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
		fx.vel, fx.born, fx.life, fx.float, fx.spin = dir * speed, os.clock(), 0.45 + math.random() * 0.3, spec.float, math.random() * 8
		table.insert(fxParts, fx)
	end
end
local function stepFx(dt)
	local now = os.clock()
	for i = #fxParts, 1, -1 do
		local fx = fxParts[i]
		local age = (now - fx.born) / fx.life
		if age >= 1 or not fx.part.Parent then
			table.remove(fxParts, i)
			if fx.part.Parent and #fxFree < Core.MAX_FX_PARTS then
				fx.part.Parent = nil
				table.insert(fxFree, fx)
			else
				fx.part:Destroy()
			end
		else
			if not fx.float then fx.vel += Vector3.new(0, -Workspace.Gravity * 0.25 * dt, 0) end
			fx.part.CFrame = (fx.part.CFrame + fx.vel * dt) * CFrame.Angles(fx.spin * dt, 0, 0)
			fx.part.Transparency = age
		end
	end
end

-- Tiny camera-safe shake via Humanoid.CameraOffset (local character only): it
-- adds to the offset already there and restores it afterwards (Core.newShake).
local shaker = Core.newShake()
local function shake(humanoid) shaker.start(humanoid, os.clock()) end
local function stepShake() shaker.step(os.clock(), math.random) end

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
-- Marks that place their FX at the hand rather than on the target.
local HAND_FX = {crumbs = true, mend = true, coins = true, water = true, attune = true, glint = true}
local function mark(state, markName)
	local character = state.character
	local def = state.def
	local reduced = reducedMotion()
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local rigKind = Core.rigType(character)
	local hand = rigKind and character:FindFirstChild(Core.HAND[rigKind])
	local handPos = if hand then hand.Position else root.Position
	-- §47 tier flourish: the twirl's peak glints from tier 7 (never with reduced motion).
	if markName == "flourish" then
		if (state.flourish or 0) >= 2 and not reduced then burst("glint", handPos, nil, reduced) end
		return
	end
	local position
	if def.fx == "splash" then
		position = (root.CFrame * CFrame.new(0, -2.5, -8)).Position
	elseif HAND_FX[def.fx] or (def.fx == "ring" and state.target == nil) then
		position = handPos
	else
		local part = partOf(state.target)
		position = if part then Core.impactPoint(part.Position, part.Size, handPos) else (root.CFrame * CFrame.new(0, 0, -3)).Position
	end
	if def.fx and (markName ~= "bob" or not reduced) then
		local scale = if markName == "impact" then Core.FLOURISH_FX[(state.flourish or 0) + 1] or 1 else 1
		burst(def.fx, position, resourceColour(partOf(state.target)), reduced, scale)
	end
	if markName == "impact" or markName == "release" or markName == "cast" then
		local id = def.sound and Core.SOUNDS[def.sound]
		if id then
			local sound = root:FindFirstChild("IsleSwingSound")
			if not sound then
				sound = Instance.new("Sound")
				sound.Name = "IsleSwingSound"
				sound.Volume = 0.35
				sound.RollOffMaxDistance = 60
				sound.Parent = root
			end
			sound.SoundId = id
			sound.PlaybackSpeed = 0.92 + math.random() * 0.16
			sound:Play()
		end
		impactHook:Fire(state.name, def.fx, position, state.isLocal)
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

-- §47 rod bend: the rod's blank parts (held model or prop) are re-welded
-- about the grip's top each frame while a fishing gesture runs, and put back
-- when it ends. The weld list is built once per gesture.
-- QC L11: a rod that is not built yet returns nil (not false), so the bend
-- retries (at most every ROD_RETRY seconds) once the held model / prop lands.
local ROD_RETRY = 0.25
local function rodWelds(s)
	local model = if s.usesHeld then s.character:FindFirstChild("HeldItem") else s.tool
	if typeof(model) ~= "Instance" then return nil end
	local grip, list = nil, {}
	for _, part in ipairs(model:GetChildren()) do
		local weld = part:IsA("BasePart") and (part:FindFirstChild("HeldWeld") or part:FindFirstChildOfClass("Weld"))
		if weld then
			if part.Name == "Grip" then grip = weld.C0 end
			if Core.ROD_PARTS[part.Name] then table.insert(list, {weld = weld, base = weld.C0}) end
		end
	end
	if not grip or #list == 0 then return nil end
	return {model = model, pivot = grip * CFrame.new(0, 0, Core.ROD_PIVOT + 0.3), welds = list}
end
local function unbend(s)
	local bend = s.bend
	if not bend then return end
	for _, w in ipairs(bend.welds) do
		if w.weld.Parent then w.weld.C0 = w.base end
	end
	s.bend = nil
end
local function bendRod(s, now)
	if s.bend and not s.bend.model.Parent then s.bend = nil end
	if s.bend == nil then
		local real = os.clock()
		if s.bendRetryAt and real < s.bendRetryAt then return end
		s.bend = rodWelds(s)
		if not s.bend then s.bendRetryAt = real + ROD_RETRY; return end
	end
	local bend = s.bend
	local degrees = Core.rodBend(s, now)
	for _, w in ipairs(bend.welds) do w.weld.C0 = Core.bendC0(w.base, bend.pivot, degrees) end
end

engine = Core.createEngine({
	now = os.clock, alive = alive, bindRig = Core.bindRig, attachTool = attachTool, watch = watch, mark = mark,
	heldFits = heldFits, hideHeld = hideHeld,
	watchHeld = function(character, onArrive)
		return character.ChildAdded:Connect(function(child)
			if child.Name == "HeldItem" then onArrive(child) end
		end)
	end,
	modelFits = function(model, name)
		local class = model:GetAttribute("HeldClass")
		return type(class) == "string" and Held.fits(Core.fitName(name), class)
	end,
	cycle = function(state)
		-- QC L1: only gestures playLocal relayed re-relay per loop (death, fidgets,
		-- attribute-driven and agility moves never do).
		if state.isLocal and state.relayName then send(state.relayName, state.target, state.itemId) end
	end,
	post = function(state, now)
		if state.def.rod then bendRod(state, now) end
	end,
	ended = function(state)
		if state.bend then unbend(state) end
	end,
})

-- §47 stance: the node's size and height pick the variant (a low rock is
-- struck from a crouch, a high vein overhead); the base name is what relays.
local function stanceOf(character, name, target)
	if not Core.STANCES[name] then return name end
	local part = partOf(target)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not part or not root then return name end
	return Core.stanceFor(name, root.Position.Y, part.Position.Y, part.Size.Y)
end
local localCombo = Core.newCombo()
local function playLocal(name, target, opts)
	local character = player.Character
	if not Core.NAMES[name] or not alive(character) then return end
	opts = opts or {}
	local itemId = opts.itemId or itemFor(name)
	-- Melee swings follow the weapon's class: slash, dagger thrust, two-handed cleave, glaive lunge.
	if name == "attack" and itemId then name = Held.attackGesture(itemId) end
	-- Gathering and fighting put the right item in hand (a temporary switch the
	-- server returns once idle); the swing uses it at once instead of a prop.
	local def = Core.GESTURES[name]
	if itemId and (def.skill or Core.MELEE_GESTURE[name] or Core.STYLE_GESTURE[name]) and Held.holdable(itemId)
		and Held.fits(Core.fitName(name), Held.classOf(Data.Items[itemId])) and heldIdOf(character) ~= itemId then
		pending.set(itemId, os.clock())
		autoHold:Fire(itemId)
	end
	local reduced = reducedMotion()
	local play = stanceOf(character, name, target)
	-- §47: weapon combos chain in order; gathering strikes extend one swing
	-- cycle per strike (the server's cadence) and flourish by tool tier.
	local variant = if def.combo then Core.comboNext(localCombo, name, os.clock()) else math.random(1, 3)
	local flourish = if (def.strike or def.rod) and not reduced then Core.flourishLevel(Data, itemId) else 0
	local state = engine.play(character, play, {
		target = partOf(target), hold = opts.hold, isLocal = true, color = Core.toolColor(Data, play, itemId),
		variant = variant, extend = opts.extend or def.strike ~= nil, reduced = reduced, flourish = flourish,
	})
	if state then
		state.itemId, state.prompt = itemId, opts.prompt
		if not opts.noRelay then state.relayName = name end
		if not opts.noRelay then send(name, target, itemId) end
	end
	return state
end

-- NPC nod (§47): the townsfolk you talk to nod back (local; NPC rigs have a
-- Neck motor and no Animator, so the Transform is ours).
local nods = {} -- [neck Motor6D] = start
local function nodNpc(model)
	local neck = model and model:FindFirstChild("Neck", true)
	if neck and neck:IsA("Motor6D") and not reducedMotion() then nods[neck] = os.clock() end
end
local function stepNods()
	if next(nods) == nil then return end
	local now = os.clock()
	for neck, start in pairs(nods) do
		local t = now - start
		if t >= Core.NOD_TIME or not neck.Parent then
			neck.Transform = CFrame.new()
			nods[neck] = nil
		else
			neck.Transform = CFrame.Angles(rad(Core.nodCurve(t)), 0, 0)
		end
	end
end

-- Prompts --------------------------------------------------------------------
local function promptInfo(prompt)
	return {action = prompt:GetAttribute("IsleAction"), item = prompt:GetAttribute("IsleItem"),
		coopResource = prompt:GetAttribute("IsleCoopResource"), text = prompt.ActionText, role = prompt:GetAttribute("TownsfolkRole")}
end
local function promptTarget(prompt)
	return partOf(prompt.Parent)
end
local function gestureFor(prompt)
	local info = promptInfo(prompt)
	-- QC L8: crafting stations alternate their gestures too (the Glass Furnace reaches sift).
	if info.action == "station" or info.action == "craftStation" then stationCounter += 1 end
	return Core.selectGesture(info, Data, stationCounter)
end
-- Deferred prompts (garden plots): the reply message picks the gesture.
local deferred = nil -- {target, token}
local deferToken = 0

ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, who)
	if who ~= player or not prompt.Enabled then return end
	if Core.DEFERRED_ACTION[prompt:GetAttribute("IsleAction")] then return end
	playLocal(gestureFor(prompt), promptTarget(prompt), {hold = true, prompt = prompt})
end)
ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt, who)
	if who ~= player then return end
	local state = player.Character and engine.get(player.Character)
	if state and state.prompt == prompt then engine.release(player.Character) end
end)
ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then return end
	if Core.DEFERRED_ACTION[prompt:GetAttribute("IsleAction")] then
		deferToken += 1
		local token = deferToken
		deferred = {target = promptTarget(prompt), token = token}
		task.delay(1.5, function()
			if deferred and deferred.token == token then
				local target = deferred.target
				deferred = nil
				playLocal("tend", target, {})
			end
		end)
		return
	end
	if prompt:GetAttribute("TownsfolkRole") then nodNpc(prompt:FindFirstAncestorOfClass("Model")) end
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
-- §42: struck gathering nodes fire (gesture, node) per swing; fishing casts with
-- mode "hold" (the bob loops) and ends with ("release") on the reel / a lost fish.
-- §47: ("bite") when the server pushes a bite snaps the rod down mid-wait.
localApi.Event:Connect(function(name, target, itemId, mode)
	if type(name) ~= "string" then return end
	local state = player.Character and engine.get(player.Character)
	if name == "release" then
		-- QC L9: ("release", node, nil, "reel") is the reel click; a plain release
		-- (the fish got away, another node was struck) plays and relays "lost".
		if state and state.name == "fish" and not state.fadeStart and mode ~= "reel" then
			playLocal("lost", state.target, {itemId = state.itemId})
			return
		end
		if state then
			engine.release(player.Character)
			if state.def.rod and not state.fadeStart then send("reel", state.target, state.itemId) end
		end
		return
	end
	if name == "bite" then
		if state and state.name == "fish" then
			state.biteAt = os.clock()
			send("bite", state.target, state.itemId)
		end
		return
	end
	playLocal(name, target, {itemId = if type(itemId) == "string" then itemId else nil, hold = mode == "hold"})
end)

-- Snapshot: tool colours + eat/drink after a consume; a deferred garden reply.
local updates = ReplicatedStorage:WaitForChild("IsleUpdate")
updates.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" then return end
	local depth = snapshot.depth
	if type(depth) == "table" then
		if type(depth.tools) == "table" then bestTools = depth.tools end
		if type(depth.equipment) == "table" then weaponId = depth.equipment.weapon end
	end
	if deferred and type(snapshot.message) == "string" and snapshot.message ~= "" then
		local target = deferred.target
		deferred = nil
		playLocal(Core.replyGesture(snapshot.message), target, {})
		return
	end
	local gesture, itemId = Core.consumeGesture(snapshot.message, Data)
	if gesture then playLocal(gesture, nil, {itemId = itemId}) end
end)

-- Remote characters ---------------------------------------------------------
local remoteDistance = {} -- [character] = distance when admitted
local remoteCombos = {} -- [character] = combo record (§47: remote combos chain the same way)
-- Admits a remote character under the cap (nearest win) and plays `name`.
local function playRemote(character, name, opts)
	local mine = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local theirs = character and character:FindFirstChild("HumanoidRootPart")
	local def = Core.GESTURES[name]
	if not mine or not theirs or not def or not (def.dead or alive(character)) then return nil end
	for c in pairs(remoteDistance) do
		if not engine.get(c) then remoteDistance[c] = nil end
	end
	local distance = (mine.Position - theirs.Position).Magnitude
	local admit, evict = Core.admitRemote(remoteDistance, character, distance)
	if not admit then return nil end
	if evict then
		engine.stop(evict)
		remoteDistance[evict] = nil
	end
	local state = engine.play(character, name, opts)
	if state then remoteDistance[character] = distance end
	return state
end
relay.OnClientEvent:Connect(function(source, name, target, itemId)
	if typeof(source) ~= "Instance" or source == player or type(name) ~= "string" or not Core.NAMES[name] then return end
	local character = source.Character
	if not character then return end
	itemId = if type(itemId) == "string" then itemId else nil
	-- Fishing beats steer a running cast instead of starting a new gesture.
	local current = engine.get(character)
	if (name == "reel" or name == "bite") and current and current.name == "fish" then
		if name == "reel" then engine.release(character) else current.biteAt = os.clock() end
		return
	end
	local def = Core.GESTURES[name]
	local combo = nil
	if def.combo then
		combo = remoteCombos[character]
		if not combo then combo = Core.newCombo(); remoteCombos[character] = combo end
	end
	local reduced = reducedMotion()
	local play = stanceOf(character, name, target)
	playRemote(character, play, {target = partOf(target), extend = true, color = Core.toolColor(Data, play, itemId),
		variant = if combo then Core.comboNext(combo, name, os.clock()) else math.random(1, 3),
		hold = def.remoteHold ~= nil, maxHold = def.remoteHold,
		flourish = if (def.strike or def.rod) and not reduced then Core.flourishLevel(Data, itemId) else 0})
end)
Players.PlayerRemoving:Connect(function(who)
	local character = who.Character
	if character then
		engine.stop(character)
		remoteDistance[character] = nil
		remoteCombos[character] = nil
	end
end)
player.CharacterRemoving:Connect(function(character) engine.stop(character) end)

-- Server-set gesture attributes (Beaconry §37 BeaconryGesture
-- "<gesture>:<seq>[:<itemId>]", Crafting CraftingGesture "<gesture>:<seq>"):
-- §47 every client watches every player's attributes, so other players see
-- kindling, campfire cooking and crafting batches without a relay.
local function playAttribute(who, name, item)
	if not name or not Core.NAMES[name] then return end
	if who == player then
		playLocal(name, nil, {itemId = item, noRelay = true})
		return
	end
	local character = who.Character
	if character then playRemote(character, name, {color = Core.toolColor(Data, name, item), variant = math.random(1, 3)}) end
end

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
-- Per-player connections (AgilityMove watch, CharacterAdded / Removing for the
-- carry pose), released on PlayerRemoving so a leaver keeps nothing alive.
local playerConns = {} -- [player] = {connections}
local function own(who, conn)
	local list = playerConns[who]
	if not list then list = {}; playerConns[who] = list end
	table.insert(list, conn)
end
Core.playerConns = playerConns -- exposed for the headless runtime test
local function watchRunner(who)
	own(who, who:GetAttributeChangedSignal("AgilityMove"):Connect(function() playAgility(who) end))
	if who:GetAttribute("AgilityMove") then task.defer(playAgility, who) end
	-- §47: kindling / campfire cooking and crafting batches, for every player.
	own(who, who:GetAttributeChangedSignal("BeaconryGesture"):Connect(function()
		playAttribute(who, Core.beaconryGesture(who:GetAttribute("BeaconryGesture")))
	end))
	own(who, who:GetAttributeChangedSignal("CraftingGesture"):Connect(function()
		local value = who:GetAttribute("CraftingGesture")
		playAttribute(who, type(value) == "string" and string.match(value, "^(%a+):%d+$") or nil, nil)
	end))
end

-- Carry pose for every character holding an item (built when its HeldItem
-- model appears or goes). Targets are fixed per character: the frame loop only
-- lerps motors, so gestures blend from and back into the carry pose. Only the
-- REMOTE_CAP nearest remote holders within range are posed (re-ranked a few
-- times a second into a reused list; no per-frame allocation).
local holders = {} -- [character] = {player, entries, weight, root, humanoid, distance, admitted}
local holderList = {} -- reused by the ranking pass
local RANK_EVERY = 0.25
local nextRank = 0
local function refreshHolder(who, character)
	holders[character] = nil
	nextRank = 0
	local model = character:FindFirstChild("HeldItem")
	local class = model and model:GetAttribute("HeldClass")
	local pose = type(class) == "string" and Core.HOLD_POSE[class]
	if not pose then return end
	local rig = Core.bindRig(character)
	if not rig then return end
	holders[character] = {player = who, entries = Core.holdTargets(rig, pose), weight = 0, class = class,
		root = character:FindFirstChild("HumanoidRootPart"), humanoid = humanoidOf(character), distance = math.huge, admitted = false}
end
local holderConns = {} -- [player] = {connections} on the current character

-- §47 body layer: landing squash, sprint lean, hit flinch, idle fidgets and
-- death for every character, posed for the local one and the BODY_CAP nearest
-- remote ones within range (re-ranked with the holders; reused list; each
-- record owns its pose buffer, so the frame loop allocates no tables).
local bodies = {} -- [character] = {player, state, entries, root, humanoid, health, distance, admitted}
local bodyList = {}
Core.bodies = bodies -- exposed for the headless runtime test
-- QC M4: every corpse within REMOTE_RANGE plays the collapse (outside the
-- body cap: death states hold no cap slot); farther ones break their joints
-- locally, the old default ragdoll. The pose never moves the root joint.
local function playDeath(who, character)
	if not character.Parent then return end
	engine.stop(character)
	if who == player then
		engine.play(character, "death", {hold = true, isLocal = true, noWatch = true})
		return
	end
	local mine = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local theirs = character:FindFirstChild("HumanoidRootPart")
	local distance = if mine and theirs then (mine.Position - theirs.Position).Magnitude else math.huge
	if Core.deathPlan(false, distance) == "play" and engine.play(character, "death", {hold = true, noWatch = true}) then return end
	pcall(function() character:BreakJoints() end)
end
local function watchHumanoid(who, character, humanoid, list)
	local b = bodies[character]
	if not b or b.humanoid == humanoid then return end
	b.humanoid, b.health, b.maxHealth = humanoid, humanoid.Health, humanoid.MaxHealth
	table.insert(list, humanoid.HealthChanged:Connect(function(health)
		local prev, prevMax = b.health, b.maxHealth
		b.health, b.maxHealth = health, humanoid.MaxHealth
		-- QC L4: a MaxHealth clamp (gear off, a buff ending) is not a hit.
		if b.admitted and Core.isHit(prev, health, prevMax, b.maxHealth) then
			Core.bodyHit(b.state, (prev - health) / math.max(1, b.maxHealth), os.clock(), reducedMotion())
		end
	end))
	-- Deferred so the old gesture's own Died handler has run first.
	table.insert(list, humanoid.Died:Connect(function() task.defer(playDeath, who, character) end))
end
local function watchCharacter(who, character)
	for _, c in ipairs(holderConns[who] or {}) do c:Disconnect() end
	local list = {}
	bodies[character] = {player = who, state = Core.newBody(), entries = Core.bindRig(character) or {},
		root = character:FindFirstChild("HumanoidRootPart"), distance = math.huge, admitted = false}
	local function changed(child)
		if child.Name == "HeldItem" then task.defer(refreshHolder, who, character) end
		if child.ClassName == "Humanoid" and child.Parent == character then watchHumanoid(who, character, child, list) end
	end
	table.insert(list, character.ChildAdded:Connect(changed))
	table.insert(list, character.ChildRemoved:Connect(changed))
	holderConns[who] = list
	local humanoid = humanoidOf(character)
	if humanoid then watchHumanoid(who, character, humanoid, list) end
	refreshHolder(who, character)
end
-- A character going away drops every per-character record (QC L2: combos too).
local function forgetCharacter(character)
	holders[character] = nil
	bodies[character] = nil
	remoteCombos[character] = nil
	remoteDistance[character] = nil
end
Core.forgetCharacter = forgetCharacter
local function watchHolder(who)
	own(who, who.CharacterAdded:Connect(function(character) watchCharacter(who, character) end))
	own(who, who.CharacterRemoving:Connect(forgetCharacter))
	if who.Character then watchCharacter(who, who.Character) end
end
local function watchPlayer(who)
	watchRunner(who)
	watchHolder(who)
end
Players.PlayerAdded:Connect(watchPlayer)
for _, who in ipairs(Players:GetPlayers()) do watchPlayer(who) end
Players.PlayerRemoving:Connect(function(who)
	for _, c in ipairs(playerConns[who] or {}) do c:Disconnect() end
	playerConns[who] = nil
	for _, c in ipairs(holderConns[who] or {}) do c:Disconnect() end
	holderConns[who] = nil
	if who.Character then forgetCharacter(who.Character) end
end)
player:GetAttributeChangedSignal("HeldItem"):Connect(function() pending.clear() end)
local function rankHolders(mine)
	table.clear(holderList)
	local hasLocal = false
	for _, h in pairs(holders) do
		if h.player == player then
			h.distance = -1
			hasLocal = true
		else
			h.distance = if mine and h.root then (h.root.Position - mine.Position).Magnitude else math.huge
		end
		table.insert(holderList, h)
	end
	Core.admitHolders(holderList, Core.REMOTE_CAP + (if hasLocal then 1 else 0), Core.REMOTE_RANGE)
end
local function stepHolders(dt)
	local mine = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local now = os.clock()
	if now >= nextRank then
		nextRank = now + RANK_EVERY
		rankHolders(mine)
	end
	for character, h in pairs(holders) do
		if not character.Parent then
			holders[character] = nil
			continue
		end
		local humanoid = h.humanoid
		if not h.admitted or (humanoid and (humanoid.Health <= 0 or humanoid.Sit)) then
			h.weight = 0
			continue
		end
		h.weight = math.min(1, h.weight + dt * 5)
		for _, e in ipairs(h.entries) do e.motor.Transform = e.motor.Transform:Lerp(e.target, h.weight) end
	end
end
Core.holders = holders -- exposed for the headless runtime test

-- Body layer step (§47, QC M2). Additive: every motor written last frame is
-- put back to its base in RunService.PreAnimation (before the Animator and
-- before any gesture fade reads Transform), and this frame's offsets go on
-- top of whatever the Animator, carry pose and gesture wrote, in Stepped.
local function restoreBodies()
	for _, b in pairs(bodies) do
		if b.dirty then
			Core.bodyRestore(b)
			b.dirty = false
		end
	end
end
local nextBodyRank = 0
local function rankBodies(mine)
	table.clear(bodyList)
	local hasLocal = false
	for character, b in pairs(bodies) do
		-- QC L11: any lost motor (respawned limb, package swap) rebinds.
		if Core.needsRebind(b.entries) then b.entries = Core.bindRig(character) or {} end
		if not b.root or not b.root.Parent then b.root = character:FindFirstChild("HumanoidRootPart") end
		if b.player == player then
			b.distance = -1
			hasLocal = true
		else
			b.distance = if mine and b.root then (b.root.Position - mine.Position).Magnitude else math.huge
		end
		table.insert(bodyList, b)
	end
	Core.admitHolders(bodyList, Core.BODY_CAP + (if hasLocal then 1 else 0), Core.REMOTE_RANGE)
end
local function stepBodies(dt)
	local now = os.clock()
	if now >= nextBodyRank then
		nextBodyRank = now + RANK_EVERY
		rankBodies(player.Character and player.Character:FindFirstChild("HumanoidRootPart"))
	end
	local reduced = reducedMotion()
	for character, b in pairs(bodies) do
		if not character.Parent then
			bodies[character] = nil
			continue
		end
		local humanoid = b.humanoid
		-- QC L3: nothing while dead, seated or platform-standing.
		if not b.admitted or Core.bodySkip(humanoid) then continue end
		local root = b.root
		local v = root and root.AssemblyLinearVelocity
		if v then
			local horizontal = math.sqrt(v.X * v.X + v.Z * v.Z)
			Core.bodyFeed(b.state, v.Y, horizontal, now, dt, reduced)
			local s = engine.get(character)
			local moving = horizontal > 4
			-- Walking away from a kneel / crouch / chest fades it out; any other
			-- swing leaves its legs to the walk cycle while moving (QC L10).
			if s and s.def.stopOnMove and moving and not s.fadeStart then engine.cancel(character) end
			engine.setMoving(character, moving)
			-- Idle fidgets: standing still with an item in hand, nothing else playing.
			local holder = holders[character]
			local still = s == nil and holder ~= nil and horizontal < 0.5 and math.abs(v.Y) < 1
			if Core.fidgetDue(b.state, now, still and not reduced, math.random()) then
				local fidget = Core.FIDGET[holder.class]
				if fidget then
					if b.player == player then
						engine.play(character, fidget, {isLocal = true})
					else
						playRemote(character, fidget, {}) -- QC L5: under the remote cap
					end
				end
			end
		end
		local pose, active = Core.bodyPose(b.state, now)
		if active then
			Core.bodyApply(b, pose)
			b.dirty = true
		end
	end
end

local preAnimation = RunService.PreAnimation
if preAnimation then preAnimation:Connect(restoreBodies) end
RunService.Stepped:Connect(function(_, dt)
	if not preAnimation then restoreBodies() end
	stepHolders(dt)
	engine.step()
	stepBodies(dt)
	stepNods()
	if #fxParts > 0 then stepFx(dt) end
	stepShake()
end)
-- Headless runtime checks (verify-held.luau) read the live tables through this hook.
if __GestureRuntimeHarness then __GestureRuntimeHarness(Core, engine) end
