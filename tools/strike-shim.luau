-- §42 test shim: the suites written before Gathering Feel harvest through mock
-- gather prompts fired on ProximityPromptService.PromptTriggered. Nodes are no
-- longer prompted (the server refuses `gather` prompts); the `strike` verb is
-- the only way to harvest. This shim routes a fired mock gather prompt through
-- real strikes instead: it stands a real (Lune) Part in for the mock as the node
-- host (GatherNode = its IsleItem, same region / owner, at its base part's
-- position) and invokes IsleAction("strike", node) until the node breaks,
-- advancing the suite's clock one swing per strike (a fishing cast waits out
-- the bite, then reels). Everything the server does is real: validation,
-- cadence, damage, the harvest, the snapshot push. Other prompts pass through.
--
--   require("./tools/strike-shim").install({signal = services.ProximityPromptService.PromptTriggered,
--       invoke = function(player, verb, item) return remote.OnServerInvoke(player, verb, item) end,
--       advance = function(seconds) clock += seconds end})
local roblox = require("@lune/roblox")
local Shim = {}
local holder = roblox.Instance.new("Folder")
holder.Name = "StrikeShimNodes"
holder.Parent = roblox.Instance.new("Workspace") -- the server only strikes nodes in a Workspace (§42 QC L8)

-- One Part per mock prompt (per-player progress and regrowth key on it).
local nodes = setmetatable({}, {__mode = "k"})
local function basePosition(mock)
	local ok, part = pcall(function() return mock:FindFirstAncestorWhichIsA("BasePart") end)
	if not ok or part == nil then return nil end
	local okP, at = pcall(function() return part.Position end)
	if okP and at then return at end
	local okC, cf = pcall(function() return part.CFrame end)
	return if okC and cf then cf.Position else nil
end
local function attr(mock, key)
	local ok, v = pcall(function() return mock:GetAttribute(key) end)
	return if ok then v else nil
end
function Shim.node(mock)
	local node = nodes[mock]
	if not node then
		node = roblox.Instance.new("Part")
		node.Name = "Node"
		node.Size = roblox.Vector3.new(1, 1, 1)
		node.Position = roblox.Vector3.new(0, 0, 0) -- (Lune keeps Position apart from CFrame)
		node.Parent = holder
		nodes[mock] = node
	end
	node:SetAttribute("GatherNode", attr(mock, "IsleItem"))
	node:SetAttribute("IsleRegion", attr(mock, "IsleRegion"))
	node:SetAttribute("OwnerUserId", attr(mock, "OwnerUserId"))
	local at = basePosition(mock)
	if at then
		node.Position = roblox.Vector3.new(at.X, at.Y, at.Z)
		node.CFrame = roblox.CFrame.new(at.X, at.Y, at.Z)
	end
	return node
end

function Shim.isGather(mock)
	if mock == nil then return false end
	return type(attr(mock, "GatherNode")) == "string" or attr(mock, "IsleAction") == "gather"
end
-- A real node host (built by world.server.lua in the suite) is struck as itself.
function Shim.target(x)
	if type(attr(x, "GatherNode")) == "string" then return x end
	return Shim.node(x)
end

-- Strikes `node` for `player` until it breaks or a strike is refused. Returns the
-- last reply and the number of strikes sent.
function Shim.breakNode(opts, player, node, limit)
	local last, sent = nil, 0
	for _ = 1, limit or 80 do
		local reply = opts.invoke(player, "strike", node)
		sent += 1
		last = reply
		if reply == nil then
			opts.advance(0.25) -- token bucket
		elseif reply.broken then
			return reply, sent
		elseif reply.cast then
			-- The bite is pushed when it happens (§42 QC L1), never in the reply:
			-- wait out the longest bite (2 s), still inside its window.
			opts.advance(2.05)
		elseif reply.ok == false and reply.reason == "cadence" then
			opts.advance(math.max(0.02, tonumber(reply.wait) or 0.1))
		elseif reply.ok == false then
			return reply, sent
		else
			opts.advance(opts.swing or 0.7)
		end
	end
	return last, sent
end

function Shim.install(opts)
	assert(opts.signal and opts.invoke and opts.advance, "strike shim: signal, invoke, advance")
	local fire = opts.signal.Fire
	opts.signal.Fire = function(self, prompt, player, ...)
		if Shim.isGather(prompt) then
			if type(prompt) == "table" and prompt.Enabled == false then return end
			Shim.lastReply, Shim.lastStrikes = Shim.breakNode(opts, player, Shim.target(prompt))
			return
		end
		return fire(self, prompt, player, ...)
	end
	return Shim
end

return Shim
